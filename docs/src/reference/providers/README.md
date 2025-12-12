# Providers

Provider management and mirroring.

## Overview

| Rule | Description |
|------|-------------|
| [provider_mirror](provider-mirror.md) | Create filesystem mirrors for providers |

## Provider Registry

Providers are managed through the `tf_providers` module extension and referenced via the provider registry:

```starlark
tf_module(
    name = "my_module",
    srcs = glob(["*.tf"]),
    providers = [
        "@tf_provider_registry//:aws_5",
        "@tf_provider_registry//:random_3",
    ],
)
```

## Provider Aliasing

Providers are aliased by major version:
- `aws_5` - AWS provider 5.x.x
- `azurerm_4` - AzureRM provider 4.x.x
- `google_6` - Google provider 6.x.x

For 0.x providers (where minor versions can have breaking changes):
- `time_0` - Time provider 0.x.x
- `tfe_0` - TFE provider 0.x.x

## provider_mirror

For advanced use cases, create custom provider mirrors:

```starlark
provider_mirror(
    name = "custom_mirror",
    providers = [
        "hashicorp/aws:5.0.0",
        "hashicorp/random:3.0.0",
    ],
)
```
