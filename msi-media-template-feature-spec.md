# MSI cabinet compression and splitting

Branch: `feat/msi-media-template`, based on `custom/base`.

Windows `vpk pack --msi --msiCompression high` enables WiX automatic embedded cabinet splitting.
Allowed levels are `none`, `low`, `medium`, `high`, and `mszip`, case-insensitively.
Invalid values and use without `--msi` or with `--noInst` fail validation.
The MSBuild task exposes `MsiCompression`, supplied by `VelopackMsiCompression`.

When specified, `MediaTemplate EmbedCab="yes" CompressionLevel="<level>"` replaces the single `Media` element.
When omitted, generated WiX source is unchanged. Fragment linking, upgrade codes, signing, setup and package creation are unchanged.
No cabinet size or external cabinet option is introduced.

Validation covers parsing, allowed values, MSI requirements, unchanged default source, compressed source,
compiled MSI media and file tables, and compression combined with fragments and explicit upgrade codes.
The existing MSI lifecycle tests cover installation and removal.
A payload above 2 GB must also be manually built and installed before relying on this option for large deployments;
record the MSI size and build duration and keep the compressed MSI safely below 2 GB.
