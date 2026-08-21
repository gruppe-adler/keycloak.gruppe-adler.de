# Custom Keycloak image

Builds Keycloak `26.6.3` with two custom extensions pulled from GitHub
Packages (Maven), and publishes the result to **GitHub Container Registry
(GHCR)** whenever a GitHub Release is published.

## How it fits together

```
extensions/pom.xml     -> lists the two extension jars + which GitHub
                           repos publish them (GitHub Packages Maven)
extensions/settings.xml -> Maven auth for GitHub Packages, injected via
                           env vars at build time (nothing secret is
                           committed here)
Dockerfile              -> 3 stages:
                             1. fetch the two jars with Maven
                             2. drop them into /opt/keycloak/providers
                                and run `kc.sh build`
                             3. copy the built server into a clean
                                Keycloak base image
.github/workflows/build.yml -> builds the Dockerfile and pushes it to
                           GHCR, triggered when a release is published
```

## One-time setup

**1. Fix the repo names in `extensions/pom.xml`.**
GitHub Packages Maven repos are per-GitHub-repository
(`https://maven.pkg.github.com/gruppe-adler/<REPO_NAME>`). Replace
`REPLACE_WITH_ARMA3_SQUAD_REPO` and `REPLACE_WITH_STEAM_IDP_REPO` with the
actual repo names under `gruppe-adler` that publish each jar.

**2. Add one repo secret.**
Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Purpose |
|---|---|
| `GH_PACKAGES_TOKEN` | A GitHub PAT (classic) with `read:packages` scope. Needed because GitHub Packages requires auth for Maven downloads even for public packages, and the built-in `GITHUB_TOKEN` can't read packages published from *other* repos. If the PAT owner needs org access to `gruppe-adler` packages, make sure SSO is authorized for it. |

That's the only secret you need to add. Pushing to GHCR uses the
automatically-provided `GITHUB_TOKEN` — no extra setup required, though the
first time an image is pushed you may want to check
**Package settings → Manage Actions access** on the resulting GHCR package
if you want it visible/linked to this repo, or set it public if you don't
want to deal with pull auth later.

## Creating a new release (triggers the build)

The workflow runs on `release: published`, so:

1. Bump anything that needs bumping first (Keycloak version in
   `Dockerfile`, extension versions in `extensions/pom.xml`) and merge
   that to `main`. **The workflow file itself must be on `main`/the
   default branch too** — GitHub reads `release`-triggered workflows from
   there, not from the tag.
2. On GitHub, go to **Releases → Draft a new release**.
3. Choose or create a tag, e.g. `v1.2.0` (the `v` prefix is expected by
   the semver tagging in the workflow).
4. Fill in a title/notes and click **Publish release** (not "Save draft" —
   drafts don't trigger the workflow).
5. Check the **Actions** tab — a "Build and push Keycloak image" run
   should start immediately.

Or trigger a build manually any time without a release, via
**Actions → Build and push Keycloak image → Run workflow**
(no image push tag semantics apply there beyond `latest`/sha).

## Resulting image tags

Each successful run on a release publishes:

- `ghcr.io/gruppe-adler/keycloak:latest`
- `ghcr.io/gruppe-adler/keycloak:<version>` (e.g. `1.2.0`, from the release tag)
- `ghcr.io/gruppe-adler/keycloak:<short-sha>`

Pull it with:

```bash
docker pull ghcr.io/gruppe-adler/keycloak:latest
```

(If the GHCR package is private, you'll need `docker login ghcr.io` with a
PAT that has `read:packages` first.)

## Building locally

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
