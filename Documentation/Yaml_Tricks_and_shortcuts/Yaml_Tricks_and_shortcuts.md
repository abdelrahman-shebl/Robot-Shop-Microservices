# YAML Tricks & Shortcuts

---

## 1) Anchors and Aliases

### The Problem

When you repeat the same block many times in a YAML file, any update requires changing every occurrence. A single typo or missed line creates an inconsistency.

```yaml
# Without anchors — version must be updated in 9 places
user:
  image:
    repository: myrepo
    version: abc123
cart:
  image:
    repository: myrepo
    version: abc123
# ... 7 more services
```

### Defining an Anchor — `&`

An anchor marks a block so it can be referenced elsewhere. The syntax is `&anchor-name` placed after the key.

```yaml
.image: &tag          # &tag is the anchor name
  repository: myrepo
  version: abc123
```

The key `.image` is intentionally dot-prefixed — see [Section 3](#3-dot-prefix-trick-for-anchor-holders) for why.

### Using an Alias — `*`

An alias references an anchor. `*tag` expands to the entire block defined at `&tag`.

```yaml
user:
  image:
    <<: *tag    # merges repository + version into image:
```

`<<:` is the YAML **merge key**. It deep-merges the referenced block into the current map instead of nesting it as a child key.

### `!!merge` for Strict Parsers

Standard `<<:` merge keys are a YAML 1.1 feature. Some parsers (and linters that use YAML 1.2) reject them. Prefixing with `!!merge` explicitly declares the type, satisfying strict parsers:

```yaml
user:
  image:
    !!merge <<: *tag
```

This is functionally identical to `<<: *tag` but passes strict validation. This is what the robot-shop `values.yaml` uses.

### Full Example from this project

```yaml
# Anchor definition — stored once at the top
.image: &tag
  repository: shebl22
  version: c5de4dd72f579146d9dd32f4360bbd9d9b44d82d

# Every service merges the same anchor
user:
  enabled: true
  image:
    !!merge <<: *tag     # expands to: repository: shebl22 / version: <sha>

cart:
  enabled: true
  image:
    !!merge <<: *tag

mongodb:
  enabled: true
  image:
    !!merge <<: *tag
```

After YAML parsing, `user.image` becomes:
```yaml
user:
  image:
    repository: shebl22
    version: c5de4dd72f579146d9dd32f4360bbd9d9b44d82d
```

### Overriding individual fields after a merge

A field declared after `<<:` overrides the merged value for that key only:

```yaml
web:
  image:
    !!merge <<: *tag
    repository: nginx   # overrides only repository; version still comes from &tag
```

---

## 2) Dot-Prefix Trick for Anchor Holders

The anchor holder key `.image` starts with a dot deliberately:

```yaml
.image: &tag
  repository: shebl22
  version: abc123
```

**Why a dot?**

- The Helm chart template code accesses values like `.Values.user.image.repository`. A key named `.image` (with the dot) does not conflict with any real chart value name because Helm's Go template engine would never walk into `.Values.".image"`.
- It signals to readers "this key is a YAML internal — not a real chart value."
- It is a common convention in large YAML files to prefix anchor-holder keys with `.` or `x-` (the `x-` prefix is Docker Compose's official extension key convention).

Docker Compose uses `x-` prefix for the same pattern:
```yaml
x-common-env: &common-env
  LOG_LEVEL: info
  REGION: us-east-1

services:
  api:
    environment:
      <<: *common-env
  worker:
    environment:
      <<: *common-env
```

---

## 3) Updating YAML Files with `yq`

`yq` is a command-line YAML processor (like `jq` but for YAML). It reads, filters, and modifies YAML files.

### Basic syntax

```bash
yq '<expression>' file.yaml          # read/print result
yq -i '<expression>' file.yaml       # in-place edit (modifies file)
```

### Reading a value

```bash
yq '.user.image.version' helm/robot-shop/values.yaml
```

### Setting a value

```bash
yq -i '.user.image.version = "newvalue"' helm/robot-shop/values.yaml
```

### Setting from an environment variable — `strenv()`

Inline shell variable substitution with `$VAR` inside single quotes does not work in bash. `yq` provides `strenv(VAR_NAME)` to read an environment variable safely:

```bash
export NEW_VERSION="abc123"
yq -i '.user.image.version = strenv(NEW_VERSION)' file.yaml
```

This is how the CI/CD pipeline updates all image versions after a build:

```bash
# From .github/workflows/CI-CD.yml
NEW_VERSION=${{ github.sha }}
yq -i '.".image".version = strenv(NEW_VERSION)' helm/robot-shop/values.yaml
```

### Quoting keys that contain special characters

yq uses `.key` notation for normal keys. If a key contains a dot, hyphen, or starts with a dot, wrap it in double quotes inside the expression:

```bash
# Key is literally ".image" (dot is part of the key name, not yq path separator)
yq '.".image".version' helm/robot-shop/values.yaml

# Key with a hyphen
yq '."my-key".value' file.yaml

# Nested: walk into .image (anchored hidden key), update version
yq -i '.".image".version = strenv(NEW_VERSION)' helm/robot-shop/values.yaml
```

**Why updating `.".image".version` updates all services:**
The anchor `&tag` is a pointer — it does not copy the data. When YAML is serialized back to disk, the anchor definition is what gets written, and all `*tag` aliases remain as references. So updating the single anchor definition propagates to every service that uses `<<: *tag`.

### Other useful `yq` operations

```bash
# Add a new key
yq -i '.newKey = "value"' file.yaml

# Delete a key
yq -i 'del(.user.image.tag)' file.yaml

# Update only if key exists
yq -i 'select(has("version")) | .version = "new"' file.yaml

# Append to a list
yq -i '.hosts += ["newhost.com"]' file.yaml

# Read multiple keys at once
yq '{version: .user.image.version, repo: .user.image.repository}' file.yaml

# Convert YAML → JSON (useful for piping into jq)
yq -o=json '.' file.yaml | jq '.user'

# Pretty-print and validate
yq '.' file.yaml

# Update a value inside an array by index
yq -i '.ingress.hosts[0].host = "new.domain.com"' file.yaml

# Update a value inside an array by matching a field
yq -i '(.ingress.tls[] | select(.secretName == "my-tls")).hosts[0] = "new.domain.com"' file.yaml
```

### Using `strenv()` vs inline variables

| Method | Works? | Why |
|--------|--------|-----|
| `yq -i ".key = $VAR"` | ✅ double quotes expand shell vars | Value gets shell-expanded before yq sees it — breaks if value has spaces or special chars |
| `yq -i '.key = "$VAR"'` | ❌ | Single quotes prevent shell expansion — literally sets `"$VAR"` as the string |
| `yq -i '.key = strenv(VAR)'` | ✅ safe | yq reads the env var directly — handles spaces, quotes, and special characters correctly |

Always prefer `strenv()` in CI pipelines.

---

## 4) Putting It Together — CI/CD Pipeline Pattern

The pipeline in `.github/workflows/CI-CD.yml` uses all of the above:

```bash
# After building and pushing all Docker images, update the single anchor
# so every service picks up the new version via their <<: *tag merges

yq -i '.".image".version = strenv(NEW_VERSION)' helm/robot-shop/values.yaml
```

What this does step by step:

1. `.".image"` — navigates to the key literally named `.image` (quoted because of the dot prefix)
2. `.version` — accesses the `version` field inside that block  
3. `= strenv(NEW_VERSION)` — sets it to the value of the `NEW_VERSION` environment variable (the git commit SHA)
4. `-i` — writes the change back to the file in-place

ArgoCD then detects the git commit, syncs the Helm chart, and every microservice Deployment gets the new image tag via its `!!merge <<: *tag`.

---

## 5) Quick Reference

| Syntax | What it does |
|--------|-------------|
| `&name` | Define an anchor named `name` on a block |
| `*name` | Reference (alias) to anchor `name` |
| `<<: *name` | Merge anchor block into current map |
| `!!merge <<: *name` | Same as above, explicit type for strict parsers |
| `.key: &name` | Define anchor on a key that is literally `.key` |
| `yq '.key'` | Read a value |
| `yq -i '.key = "val"'` | Set a value in-place |
| `yq -i '.key = strenv(VAR)'` | Set from env variable safely |
| `yq '."dotted.key"'` | Access key whose name contains a dot |
| `yq -o=json '.'` | Convert YAML to JSON |
| `yq 'del(.key)'` | Delete a key |
| `yq '.list += ["item"]'` | Append to a list |
