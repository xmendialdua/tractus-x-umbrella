# SharedIDP Realm Configuration

## Purpose

This directory is intentionally left empty (except for this README). The SharedIDP realm configuration is managed entirely through Helm values and environment variables, not through JSON files.

## Problem & Solution

### The Problem

The sharedidp init-container uses the following command to copy realm files:
```bash
cp -R /import/catenax-shared/realms/* /app/realms
```

This command fails with `cp: can't stat '/import/catenax-shared/realms/*': No such file or directory` when the directory is empty or contains only hidden files (like `.gitkeep`).

The shell wildcard `*` doesn't match:
- Empty directories
- Hidden files starting with `.` (like `.gitkeep`)

### The Solution

This `README.md` file serves as a visible placeholder to prevent the `cp` command from failing. The wildcard `*` will match this file, allowing the copy command to succeed even though there are no actual realm configuration files.

### Why Not Modify the Chart?

The ideal solution would be to modify the init-container command in the sharedidp Helm chart to handle empty directories:
```bash
cp -R /import/catenax-shared/realms/. /app/realms/ 2>/dev/null || true
```

However, since we're using a pre-packaged chart, we cannot modify its templates without forking the entire chart.

## Configuration Method

SharedIDP realms are configured through:
- Helm values in `values-ovh-hosts-portal.yaml`
- Environment variables passed to the init-container
- The `realmSeeding.realms.cxOperator` section in the values file

Key configuration:
```yaml
sharedidp:
  realmSeeding:
    realms:
      cxOperator:
        centralidp: "http://centralidp.<IP>.nip.io"
```
