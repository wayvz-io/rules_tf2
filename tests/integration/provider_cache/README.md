# Provider Cache Test Module

This module tests that per-module provider caching works correctly.
It uses only the null provider to verify that the cache is minimal.

## Purpose

- Validates that per-module provider mirrors only include needed providers
- Ensures symlinks are used instead of file copies
- Verifies platform-aware selection works correctly
