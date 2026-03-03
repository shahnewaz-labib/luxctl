use std::path::PathBuf;

use color_eyre::eyre::Result;

use crate::api::LighthouseAPIClient;
use crate::commands::run;
use crate::config::Config;
use crate::message::Message;
use crate::state::ProjectState;
use crate::ui::UI;
use crate::{oops, say};

/// handle `luxctl terminal list`
pub async fn list() -> Result<()> {
    let config = Config::load()?;
    if !config.has_auth_token() {
        oops!("not authenticated. Run: `luxctl auth --token $token`");
        return Ok(());
    }

    let client = LighthouseAPIClient::from_config(&config);
    match client.terminals().await {
        Ok(terminals) => {
            Message::print_terminals(&terminals);
        }
        Err(err) => {
            oops!("failed to fetch terminals: {}", err);
        }
    }

    Ok(())
}

/// handle `luxctl terminal start --slug <slug> [--workspace <path>] [--lang <lang>]`
pub async fn start(slug: &str, workspace: &str, lang: Option<&str>) -> Result<()> {
    let config = Config::load()?;
    if !config.has_auth_token() {
        oops!("not authenticated. Run: `luxctl auth --token $token`");
        return Ok(());
    }

    let workspace_path = std::path::Path::new(workspace);
    let absolute_workspace = if workspace_path.is_absolute() {
        workspace_path.to_path_buf()
    } else {
        std::env::current_dir()
            .map_err(|e| color_eyre::eyre::eyre!("cannot get cwd: {}", e))?
            .join(workspace_path)
    };

    let canonical = absolute_workspace
        .canonicalize()
        .unwrap_or(absolute_workspace);

    let workspace_str = canonical.to_string_lossy().to_string();

    // reuse ProjectState with empty tasks — terminals don't have multi-task state.
    // lang is stored in the runtime field (same purpose: selecting go/rust/c).
    let mut state = ProjectState::load(config.expose_token())?;
    state.set_active(slug, slug, &[], &workspace_str, lang);
    state.save(config.expose_token())?;

    UI::success(&format!("active terminal: {}", slug));
    UI::kv("workspace", &workspace_str);
    if let Some(lang) = lang {
        UI::kv("language", lang);
    }
    UI::note("run `luxctl terminal run` to validate your solution");

    Ok(())
}

/// handle `luxctl terminal run [--detailed]`
pub async fn run_active(detailed: bool) -> Result<()> {
    let config = Config::load()?;
    if !config.has_auth_token() {
        oops!("not authenticated. Run: `luxctl auth --token $token`");
        return Ok(());
    }

    let state = ProjectState::load(config.expose_token())?;
    let active = match state.get_active() {
        Some(l) => l.clone(),
        None => {
            oops!("no active terminal");
            say!("run `luxctl terminal start --slug <slug>` first");
            return Ok(());
        }
    };

    let client = LighthouseAPIClient::from_config(&config);

    let terminal = match client.terminal_by_slug(&active.slug).await {
        Ok(t) => t,
        Err(err) => {
            oops!("failed to fetch terminal '{}': {}", active.slug, err);
            return Ok(());
        }
    };

    let workspace = PathBuf::from(&active.workspace);
    let lang = active.runtime.as_deref();
    run::run_terminal(&terminal, &workspace, lang, detailed).await
}

/// handle `luxctl terminal status`
pub fn status() -> Result<()> {
    let config = Config::load()?;
    if !config.has_auth_token() {
        oops!("not authenticated. Run: `luxctl auth --token $token`");
        return Ok(());
    }

    let state = ProjectState::load(config.expose_token())?;

    if let Some(project) = state.get_active() {
        UI::kv_aligned("terminal", &project.slug, 14);
        UI::kv_aligned("workspace", &project.workspace, 14);
    } else {
        UI::info("no active terminal");
        UI::note("run `luxctl terminal start --slug <slug>` to start one");
    }

    Ok(())
}

/// handle `luxctl terminal stop`
pub fn stop() -> Result<()> {
    let config = Config::load()?;
    if !config.has_auth_token() {
        oops!("not authenticated. Run: `luxctl auth --token $token`");
        return Ok(());
    }

    let mut state = ProjectState::load(config.expose_token())?;

    if state.get_active().is_some() {
        let slug = state
            .get_active()
            .map(|l| l.slug.clone())
            .unwrap_or_default();
        state.clear_active();
        state.save(config.expose_token())?;
        UI::success(&format!("stopped terminal: {}", slug));
    } else {
        UI::info("no active terminal to stop");
    }

    Ok(())
}
