# GitLab code transfer utility

This repository contains a serial GitLab repository migration utility. It copies Git history, branches, tags, and Git LFS objects while keeping temporary disk usage bounded. It can resume interrupted work and has a `--sync` mode that compares branch and tag SHAs before transferring changed repositories.

The program does not store credentials. Enter the source password or token and the destination token only when prompted, or provide them through the `SRC_TOKEN` and `DST_TOKEN` environment variables. Keep the migration manifest and work directory outside source control.

## Run

Preview a migration:

```sh
python3 outputs/gitlab-transfer/migrate.py \
  --source https://source-gitlab.example \
  --target https://target-gitlab.example \
  --work-dir ./migration-work
```

Add `--execute` to transfer repositories. When the source GitLab API is unavailable, use a JSON manifest captured from the authenticated source web UI and pass `--source-manifest path/to/manifest.json`; this mode asks for the source Git password for Git fetches. Use `--sync --execute` for a later incremental synchronization.

The utility processes one bare repository at a time, checks available disk space, verifies branch and tag object IDs, retries transient gateway failures, and removes temporary repositories after each project. It refuses to overwrite an unowned or conflicting non-empty destination repository.

## Test

```sh
PYTHONPATH=outputs/gitlab-transfer python3 -m unittest outputs/gitlab-transfer/test_migrate.py -v
```

Install Git LFS on the machine that runs the utility. The optional `outputs/gitlab-transfer/bin/git-lfs` helper is platform-specific and is intentionally kept out of this public repository; use a compatible system installation instead.

Migration manifests, state files, logs, and archives are intentionally ignored because they can contain internal project metadata.

