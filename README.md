# Custom Keycloak image

Builds Keycloak `26.6.3` with two custom extensions pulled from GitHub
Packages (Maven), and pushes the result to Docker Hub via GitHub Actions.

- `de.grad.keycloak.squad:keycloak-grad-arma3-squad:0.0.2`
- `de.grad.keycloak.steam:keycloak-steam-idp:0.0.7`

## 1. Fix the repository names (one-time)

GitHub Packages Maven repos are per-GitHub-repository:
`https://maven.pkg.github.com/gruppe-adler/<REPO_NAME>`

Open `extensions/pom.xml` and replace:
- `REPLACE_WITH_ARMA3_SQUAD_REPO` → the repo name (under `gruppe-adler`) that publishes `keycloak-grad-arma3-squad`
- `REPLACE_WITH_STEAM_IDP_REPO` → the repo name that publishes `keycloak-steam-idp`

If both jars are published from the same repo, point both entries at that repo.

## 2. Required GitHub Actions secrets

Set these in this repo under **Settings → Secrets and variables → Actions**:

| Secret | Purpose |
|---|---|
| `GH_PACKAGES_TOKEN` | A GitHub PAT (classic) with `read:packages` scope, used to download the extension jars from GitHub Packages. GitHub Packages requires auth for Maven downloads even on public packages, so a plain `GITHUB_TOKEN` isn't enough unless it belongs to the same repo the package was published from. If your PAT owner needs org access to `gruppe-adler` packages, also make sure SSO is authorized for the token. |
| `DOCKERHUB_USERNAME` | Docker Hub username to push to `gruppeadler/keycloak`. |
| `DOCKERHUB_TOKEN` | Docker Hub access token (Account Settings → Security → New Access Token). |

`github.actor` is used automatically as the Maven username for `GH_PACKAGES_TOKEN`, so no separate secret is needed for that.

## 3. What the workflow does

On push to `main`, on version tags (`vX.Y.Z`), and manually via
`workflow_dispatch`:

1. Builds the Dockerfile with BuildKit, passing the GitHub Packages
   credentials in as **build secrets** (`--mount=type=secret`), so they
   never land in an image layer or `docker history`.
2. Pushes to `gruppeadler/keycloak` on Docker Hub, tagged:
   - `latest` (on `main`)
   - the semver tag (on `vX.Y.Z` tags)
   - the short commit SHA (always)

Pull requests build the image (to catch breakage) but do not push.

## 4. Building locally

```bash
export DOCKER_BUILDKIT=1
docker buildx build \
  --secret id=gh_actor,env=GH_ACTOR \
  --secret id=gh_token,env=GH_TOKEN \
  -t keycloak-custom:local \
  .
```

Where `GH_ACTOR` is your GitHub username and `GH_TOKEN` is a PAT with
`read:packages` scope, exported in your shell first.

## 5. Bumping the Keycloak version

Change the default in `Dockerfile`:

```dockerfile
ARG KEYCLOAK_VERSION=26.6.3
```

or pass `--build-arg KEYCLOAK_VERSION=...` at build time.

## 6. Bumping an extension version

Edit the `<version>` in `extensions/pom.xml` for the relevant dependency.
