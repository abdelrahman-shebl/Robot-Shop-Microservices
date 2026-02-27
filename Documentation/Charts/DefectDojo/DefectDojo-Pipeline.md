# DefectDojo: CI/CD Pipeline Integration

Companion file: [defectdojo.md](defectdojo.md)

---

## 1) The Two-Pipeline Architecture

Security scanning and DefectDojo uploading are intentionally split into two separate pipelines:

```
  Push to main / feature/*
         │
         ▼
  ┌──────────────────────────────────────────────────────┐
  │  CI-CD.yml  (runs automatically on every push)       │
  │                                                      │
  │  semgrep_scan ──────────────────────────────────┐   │
  │  gitleaks_scan ─────────────────────────────────┤   │
  │  image_scan (matrix: 10 apps) ──────────────────┤   │
  │  dast_scan ─────────────────────────────────────┤   │
  │                                                  │   │
  │  consolidate_reports ◄──────────────────────────┘   │
  │       └── uploads: final-security-bundle             │
  │                                                      │
  │  update-k8s-values (updates Helm values → ArgoCD)    │
  └──────────────────────────────────────────────────────┘
         │
         │  final-security-bundle lives in GitHub Actions artifacts
         │  (persisted between workflow runs)
         │
  Manual trigger (workflow_dispatch)
         │
         ▼
  ┌──────────────────────────────────────────────────────┐
  │  DefectDojo.yml  (triggered manually when needed)    │
  │                                                      │
  │  1. Download final-security-bundle                   │
  │  2. Fetch API token                                  │
  │  3. Upload each scan to the correct DD product       │
  └──────────────────────────────────────────────────────┘
```

**Why split?** DefectDojo ingestion is a secondary concern — it should not block the deployment pipeline. The CI/CD pipeline focuses on building, scanning, and deploying. DefectDojo upload is done separately, on demand, after the CI run completes.

---

## 2) Scan Jobs: What Each Produces

### Semgrep (SAST)

```yaml
- name: Run semgrep scans
  run: semgrep scan --config auto \
    --sarif-output=semgrep-reports.sarif \
    --json-output=semgrep-reports.json \
    --severity ERROR --severity WARNING

- name: Upload semgrep-reports
  uses: actions/upload-artifact@v6.0.0
  with:
    name: semgrep-reports       # artifact name (matches *-reports pattern)
    path: "semgrep-reports*"    # uploads BOTH .sarif AND .json
```

| File | Used by |
|------|---------|
| `semgrep-reports.sarif` | DefectDojo import (scan_type: SARIF) |
| `semgrep-reports.json` | Kept as a backup / human-readable reference |

**DefectDojo import type:** `SARIF` — a standardized format for static analysis results. Semgrep natively outputs SARIF, so no conversion is needed.

---

### Gitleaks (Secrets Scanning)

```yaml
- name: Run Gitleaks
  run: ./gitleaks detect --report-path gitleaks-report.json --report-format json || true
  # The '|| true' ensures the pipeline does not fail hard on found secrets.
  # The report is still generated and uploaded regardless.

- name: Upload gitleaks-reports
  uses: actions/upload-artifact@v4
  with:
    name: gitleaks-reports      # artifact name (matches *-reports pattern)
    path: gitleaks-report.json
```

| File | Used by |
|------|---------|
| `gitleaks-report.json` | DefectDojo import (scan_type: Gitleaks Scan) |

**DefectDojo import type:** `Gitleaks Scan` — NOT generic JSON. DefectDojo has a dedicated importer that understands Gitleaks' specific JSON schema: `{ "Description", "StartLine", "EndLine", "Secret", "File", "RuleID" }`. Using the wrong scan_type (e.g., "Generic Findings Import") would fail to parse the findings correctly.

---

### Docker Scout (Container + SCA)

This job runs as a **matrix** — one parallel execution per application image:

```yaml
strategy:
  fail-fast: false
  matrix:
    app: [cart, mongo, payment, catalogue, dispatch, mysql, ratings, shipping, user, web]
```

For each app:

```yaml
- name: Docker Scout
  uses: docker/scout-action@v1.18.2
  with:
    command: quickview, cves
    image: ${{ vars.DOCKERHUB_USERNAME }}/rs-${{ matrix.app }}:${{github.sha}}
    only-severities: critical,high
    sarif-file: ${{ matrix.app }}-reports.sarif    # e.g., cart-reports.sarif

- name: Upload a Build Artifact
  uses: actions/upload-artifact@v6.0.0
  with:
    name: ${{ matrix.app }}-reports    # e.g., artifact name: cart-reports
    path: ${{ matrix.app }}-reports.sarif
```

This produces 10 separate artifacts:
```
cart-reports       → cart-reports.sarif
mongo-reports      → mongo-reports.sarif
payment-reports    → payment-reports.sarif
catalogue-reports  → catalogue-reports.sarif
dispatch-reports   → dispatch-reports.sarif
mysql-reports      → mysql-reports.sarif
ratings-reports    → ratings-reports.sarif
shipping-reports   → shipping-reports.sarif
user-reports       → user-reports.sarif
web-reports        → web-reports.sarif
```

**DefectDojo import type:** `SARIF` — Docker Scout outputs standard SARIF. Each app gets its own product in DefectDojo (`Robot-Shop-Microservices-Image-cart`, etc.) so findings stay separated per service.

---

### OWASP ZAP (DAST)

```yaml
- name: OWASP ZAP Baseline Scan
  uses: zaproxy/action-baseline@v0.14.0
  with:
    target: 'http://localhost:8080'
    allow_issue_writing: false
    fail_action: false          # don't block the pipeline on DAST findings
    cmd_options: '-x report_xml.xml'    # -x = XML output format

- name: Upload DAST Report
  uses: actions/upload-artifact@v4
  with:
    name: zap-dast-reports      # artifact name (matches *-reports pattern)
    path: report_xml.xml
```

| File | Used by |
|------|---------|
| `report_xml.xml` | DefectDojo import (scan_type: ZAP Scan) |

**DefectDojo import type:** `ZAP Scan` — NOT generic XML. DefectDojo has a dedicated ZAP importer that parses ZAP's XML report schema (`OWASPZAPReport`). The `-x` flag in ZAP's command produces this specific XML format.

---

## 3) The Consolidation Step

After all scan jobs complete, `consolidate_reports` merges every artifact into a single bundle:

```yaml
consolidate_reports:
  needs: [image_scan, semgrep_scan, gitleaks_scan, dast_scan]
  if: always()     # run even if some scans fail
  steps:
    - name: Download All Individual Artifacts
      uses: actions/download-artifact@v6
      with:
        pattern: "*-reports"    # matches ALL artifacts ending in "-reports"
        path: all-reports       # downloads every match into this directory
        merge-multiple: true    # flattens into one flat folder (no subfolders)

    - name: Upload Single Unified Zip
      uses: actions/upload-artifact@v4
      with:
        name: final-security-bundle   # the single deliverable artifact
        path: all-reports/            # the merged flat directory
```

### How the pattern match works

The pattern `"*-reports"` matches all artifact names ending in `-reports`:

```
semgrep-reports      ✅ matched
gitleaks-reports     ✅ matched
cart-reports         ✅ matched
mongo-reports        ✅ matched
payment-reports      ✅ matched
... (all 10 image scans)
zap-dast-reports     ✅ matched
```

The `merge-multiple: true` flag is critical — without it, each artifact would be downloaded into its own subfolder (`all-reports/cart-reports/cart-reports.sarif`). With it, all files land flat at `all-reports/*.sarif`, `all-reports/*.json`, `all-reports/*.xml`.

### Resulting flat structure of `final-security-bundle`

```
final-security-bundle/
├── semgrep-reports.sarif
├── semgrep-reports.json
├── gitleaks-report.json
├── cart-reports.sarif
├── mongo-reports.sarif
├── payment-reports.sarif
├── catalogue-reports.sarif
├── dispatch-reports.sarif
├── mysql-reports.sarif
├── ratings-reports.sarif
├── shipping-reports.sarif
├── user-reports.sarif
├── web-reports.sarif
└── report_xml.xml
```

This single zip is what the DefectDojo pipeline downloads.

---

## 4) The DefectDojo Upload Pipeline

The upload pipeline runs on `workflow_dispatch` (manual trigger only).

### Step 1: Download the artifact bundle

```yaml
- name: Download via GitHub CLI
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    # Finds and downloads the latest 'final-security-bundle' artifact from this repo
    gh run download --name final-security-bundle --dir all-reports
```

The GitHub CLI (`gh`) finds the most recent workflow run that produced `final-security-bundle` and downloads it into `all-reports/`. No need to specify which run — it always takes the latest.

---

### Step 2: Fetch the API token dynamically

```yaml
- name: Fetch DefectDojo API Token
  id: get-token
  run: |
    TOKEN=$(curl -s -X POST "${{ secrets.DEFECTDOJO_URL }}/api/v2/api-token-auth/" \
      -H "Content-Type: application/json" \
      -d '{"username":"${{ secrets.DD_USERNAME }}","password":"${{ secrets.DD_PASSWORD }}"}' \
      | jq -r .token)
    
    if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
      echo "Error: Failed to retrieve API token."
      exit 1
    fi
    
    echo "::add-mask::$TOKEN"       # mask token so it never appears in logs
    echo "DD_TOKEN=$TOKEN" >> $GITHUB_ENV
```

This approach fetches a short-lived API token at runtime rather than storing a long-lived token in GitHub Secrets. The `::add-mask::` instruction tells GitHub Actions to replace any occurrence of this value in all subsequent log lines with `***`.

---

### Step 3: Bulk upload — scan type mapping

This is where the DefectDojo format requirements matter most. Each file must be sent with the correct `scan_type` parameter, otherwise DefectDojo cannot parse the findings.

```bash
cd all-reports

DOJO_URL="${{ secrets.DEFECTDOJO_URL }}/api/v2/import-scan/"
AUTH_HEADER="Authorization: Token $DD_TOKEN"
ENGAGEMENT="Automated-CI-CD"
PRODUCT_TYPE="Robot-Shop-App"
```

#### SAST (Semgrep → SARIF)

```bash
curl -X POST "$DOJO_URL" \
  -H "$AUTH_HEADER" \
  -F "scan_type=SARIF" \                          # DefectDojo SARIF importer
  -F "product_type_name=$PRODUCT_TYPE" \
  -F "product_name=Robot-Shop-Microservices-Code" \
  -F "engagement_name=$ENGAGEMENT" \
  -F "auto_create_context=True" \                 # creates product/engagement if not exists
  -F "file=@semgrep-reports.sarif"
```

#### Secrets (Gitleaks → JSON)

```bash
curl -X POST "$DOJO_URL" \
  -H "$AUTH_HEADER" \
  -F "scan_type=Gitleaks Scan" \                  # must be exactly "Gitleaks Scan"
  -F "product_type_name=$PRODUCT_TYPE" \
  -F "product_name=Robot-Shop-Microservices-Secrets" \
  -F "engagement_name=$ENGAGEMENT" \
  -F "auto_create_context=True" \
  -F "file=@gitleaks-report.json"
```

#### Container scans (Docker Scout → SARIF, per app)

```bash
# Loops over every *-reports.sarif except the semgrep one
for report in *-reports.sarif; do
  if [[ "$report" != "semgrep-reports.sarif" ]]; then
    APP_NAME=$(echo "$report" | sed 's/-reports.sarif//')    # extract "cart", "mongo", etc.
    
    curl -X POST "$DOJO_URL" \
      -H "$AUTH_HEADER" \
      -F "scan_type=SARIF" \
      -F "product_type_name=$PRODUCT_TYPE" \
      -F "product_name=Robot-Shop-Microservices-Image-$APP_NAME" \   # one product per service
      -F "engagement_name=$ENGAGEMENT" \
      -F "auto_create_context=True" \
      -F "file=@$report"
  fi
done
```

#### DAST (OWASP ZAP → XML)

```bash
curl -X POST "$DOJO_URL" \
  -H "$AUTH_HEADER" \
  -F "scan_type=ZAP Scan" \                       # must be exactly "ZAP Scan"
  -F "product_type_name=$PRODUCT_TYPE" \
  -F "product_name=Robot-Shop-Microservices-Web" \
  -F "engagement_name=$ENGAGEMENT" \
  -F "auto_create_context=True" \
  -F "file=@report_xml.xml"
```

---

## 5) Scan Type Reference: What DefectDojo Requires

This is the most common failure point. The `scan_type` parameter must exactly match one of DefectDojo's registered importers:

| Tool | Output file | Output format | DD scan_type |
|------|-------------|---------------|--------------|
| Semgrep | `semgrep-reports.sarif` | SARIF | `SARIF` |
| Gitleaks | `gitleaks-report.json` | Custom JSON | `Gitleaks Scan` |
| Docker Scout | `<app>-reports.sarif` | SARIF | `SARIF` |
| OWASP ZAP | `report_xml.xml` | ZAP XML | `ZAP Scan` |

**Why does this matter?** DefectDojo does not auto-detect file format. It uses the `scan_type` to select which parser class to run on the file. If you send a Gitleaks JSON file with `scan_type=Generic Findings Import`, the parser will look for generic fields (`title`, `severity`, `description`) and find none — resulting in zero findings imported with no error message.

Other commonly needed scan types for future expansion:

| Tool | scan_type |
|------|-----------|
| Trivy | `Trivy Scan` |
| Snyk | `Snyk Scan` |
| Checkov | `Checkov Scan` |
| Bandit | `Bandit Scan` |
| OWASP Dependency-Check | `Dependency Check Scan` |
| Grype | `Anchore Grype` |
| Prowler | `Prowler V3` |

---

## 6) GitHub Secrets Required

| Secret | Used for |
|--------|----------|
| `DEFECTDOJO_URL` | Base URL of the DefectDojo instance, e.g., `https://defectdojo.yourdomain.com` |
| `DD_USERNAME` | DefectDojo admin username |
| `DD_PASSWORD` | DefectDojo admin password |
| `DOCKERHUB_USERNAME` | Docker Hub repo for image builds (also set as a repo Variable) |
| `DOCKERHUB_TOKEN` | Docker Hub token for pushing images |
| `GITHUB_TOKEN` | Automatically provided by GitHub Actions; needed for `gh run download` |

---

## 7) What the DefectDojo Product Tree Looks Like After Upload

After running the DefectDojo pipeline, the product structure in DefectDojo looks like:

```
Product Type: Robot-Shop-App
├── Product: Robot-Shop-Microservices-Code
│   └── Engagement: Automated-CI-CD
│       └── Test: SARIF (Semgrep findings)
│
├── Product: Robot-Shop-Microservices-Secrets
│   └── Engagement: Automated-CI-CD
│       └── Test: Gitleaks Scan (leaked credentials)
│
├── Product: Robot-Shop-Microservices-Image-cart
│   └── Engagement: Automated-CI-CD
│       └── Test: SARIF (Docker Scout CVEs for cart)
│
├── Product: Robot-Shop-Microservices-Image-mongo
│   └── (same)
│
├── ... (one product per microservice)
│
└── Product: Robot-Shop-Microservices-Web
    └── Engagement: Automated-CI-CD
        └── Test: ZAP Scan (DAST findings)
```

Each product has its own finding list, deduplication history, and risk tracking. Findings that appear in multiple consecutive uploads are automatically marked as recurring — not re-created as new findings.
