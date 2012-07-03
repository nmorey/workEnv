# workEnv

`workEnv` is a lightweight, object-oriented framework and command-line interface (`wenv`) designed to easily create, configure, and switch between isolated `'dev'` environments on a single workstation.

Instead of running heavy virtual machines or container layers, `workEnv` implements user-space, chroot-like environment isolation. It creates a dedicated directory tree for each environment and spawns custom, isolated Bash subshells. Within these subshells, paths (`PATH`, `LD_LIBRARY_PATH`, `MANPATH`, etc.), environment variables, prompt labels, and local startup profiles are dynamically configured and isolated.

---

## Table of Contents

- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [Working with 'dev' Environments as Chroots](#working-with-dev-environments-as-chroots)
- [Customizing Configurations & Environments](#customizing-configurations)
- [Command Reference](#command-reference)
- [Environment Variables](#environment-variables)
- [License](#license)

---

## Requirements

To use `workEnv`, your workstation should meet the following requirements:

* **Shell:** Bash (highly recommended as the interactive shell)
* **Ruby:** Version `2.7` or higher

---

## Getting Started

### 1. Add `wenv` to your `PATH` & Enable Auto-Completion

Add the following snippet to your `~/.bashrc` to make the `wenv` executable accessible globally and load smart command-line auto-completion:

```bash
export WORK_ENV_SCRIPTS_DIR=${WORK_ENV_SCRIPTS_DIR:-/path/to/workEnv/git/}
if [ -d "${WORK_ENV_SCRIPTS_DIR}" ]; then
   export PATH="${WORK_ENV_SCRIPTS_DIR}/bin${PATH:+:$PATH}"
   if [ -f "${WORK_ENV_SCRIPTS_DIR}/workrc-completion.sh" ]; then
        . "${WORK_ENV_SCRIPTS_DIR}/workrc-completion.sh"
   fi
fi
```

### 2. Configure Environment Storage Directory

By default, `workEnv` looks for environments in `/work1/$(whoami)/work-envs`. You can customize this storage root by setting the `WORK_ENVS` environment variable in your shell profile:

```bash
export WORK_ENVS="/your/custom/envs/path"
```

---

## Working with 'dev' Environments as Chroots

A `'dev'` environment is an empty, clean base chroot directory that is initialized without external packages or dependencies. This allows you to construct custom toolchains or development paths from scratch.

### 1. Initializing the Chroot (`create`)

Initialize a new empty development environment:

```bash
wenv create --name my-chroot --type dev
```

This creates a dedicated environment folder at `${WORK_ENVS}/my-chroot/`.

### 2. Populating your Environment

Once the directory is created, you can manually populate it. For example, you can copy or install custom compiler versions, custom compiled libraries, or specific toolchains under `${WORK_ENVS}/my-chroot/bin/` and `${WORK_ENVS}/my-chroot/lib/`.

### 3. Entering the Chroot Subshell (`switch`)

To activate and enter your customized environment:

```bash
wenv switch my-chroot
```

This spawns a new interactive Bash subshell configured specifically for that environment. Under the hood:
- It dynamically generates an isolated `.switch_env` profile within the environment folder.
- It overrides path definitions to prioritize the environment's folders (`PATH`, `LD_LIBRARY_PATH`, `MANPATH`, etc.).
- It prepends the environment's name to your terminal prompt (e.g. `[my-chroot] user@host:~$`) to make the active scope clear.
- Typing `exit` (or pressing `Ctrl+D`) cleanly exits the subshell and returns you to your standard host environment.

### 4. Customizing Shell Startup Scripts

When you switch into an environment, `workEnv` triggers a startup profile loading lifecycle. You can configure custom hooks, environment variables, or aliases at different levels:

* **Global profile:** Create and modify `~/.config/workEnv/bashrcs/.bashrc` to execute startup hooks whenever *any* environment is loaded.
* **Environment-specific profile:** Create and modify `~/.config/workEnv/bashrcs/<env_name>` (e.g., `~/.config/workEnv/bashrcs/my-chroot`) to execute hooks and export custom configurations *only* when entering that specific environment.

---

## Customizing Configurations

Global configurations and parameters are stored inside `$XDG_CONFIG_HOME/workEnv/` (defaulting to `~/.config/workEnv/`).

You can customize the framework behavior using the `wenv config` action:

### Setting Custom Environment Locations
If you have chroot environments stored outside your main `WORK_ENVS` directory, you can register custom mappings:
```bash
wenv config --custom-env-dirs label1=/path/to/custom/dir,my-sandbox=/home/user/sandbox --save-config
```

### Disabling Confirmation Prompts
Skip confirmation checks before removing environments:
```bash
wenv config --no-confirm-delete --save-config
```

### Viewing Config Options
To inspect active settings:
```bash
wenv config --show-config
```

---

## Command Reference

| Command | Description |
| :--- | :--- |
| **`create`** | Initialize a new, empty `'dev'` environment. |
| **`switch`** | Spawn and enter an isolated interactive Bash subshell for the specified environment. |
| **`list`** | Display all registered environments and their configuration. |
| **`rm`** | Safely delete an environment directory and remove its registration. |
| **`rename`** | Rename an environment. |
| **`clean`** | Wipe all custom files in an environment directory, leaving an empty chroot shell. |
| **`get`** | Retrieve parameters and configurations of the active environment. |
| **`config`** | View, edit, and save global or local `workEnv` parameters. |
| **`help`** | Display manual and help listings. |

---

## Environment Variables

| Variable | Description |
| :--- | :--- |
| **`WORK_ENVS`** | Specifies the top-level directory where environments are stored. (Default: `/work1/$(whoami)/work-envs`) |
| **`WORK_ENV_CUSTOM_COLOR_START`** | Bash escape sequence defining the starting color for the shell prompt prefix. |
| **`WORK_ENV_CUSTOM_COLOR_STOP`** | Bash sequence defining the ending color for the prompt prefix. |
| **`WORK_ENV_LOADING_BASHRC`** | Automatically set while sourcing bashrc profiles; allows you to write custom conditional loading scripts. |
| **`XDG_CONFIG_HOME`** | Configures the path to `workEnv` config storage. If unset, defaults to `~/.config/workEnv/`. |
| **`WORK_ENV_SCRIPTS_DIR`** | Set by `workEnv` upon entering a subshell; points to the installation directory of the `workEnv` scripts. |
| **`WORK_ENV_CURRENT`** | Set by `workEnv` upon entering a subshell; holds the active environment name. |
| **`WORK_ENV_CURRENT_PATH`** | Set by `workEnv` upon entering a subshell; holds the filesystem path to the active environment. |
| **`WORK_ENV_CURRENT_TYPE`** | Set by `workEnv` upon entering a subshell; holds the active environment class type (e.g. `dev`). |

---

## License

This project is licensed under the terms of the **GNU General Public License Version 3 (GPL-3.0-or-later)**. See the `LICENSE` file for the full terms and conditions.
