# Feature spec: additional WiX fragment in the MSI

## Purpose

Let the packager add their own WiX source to the MSI that `vpk pack --msi` generates. The MSI template is an embedded resource with no extension point, so today anything beyond what vpk generates means forking vpk or post-processing the built MSI (which also breaks its signature).

## Supported use case

Applications that need machine-level installation steps that only Windows Installer should own, so that they get rollback, repair and clean uninstall. Examples:
- installing and starting a Windows service (`ServiceInstall` / `ServiceControl`), for example a helper that applies updates to a per-machine install on behalf of standard users;
- registry values under HKLM, file associations or URL protocols the template does not cover;
- extra files outside the app folder (for example under ProgramData) and permissions on them;
- firewall rules or event log sources (through WiX extensions).

Velopack's install hooks are no substitute: in the MSI they run impersonated as the installing user, so whether they have admin rights depends on how the MSI was launched, and Windows Installer does not track what they do.

## Behaviour

- Opt-in; without the option the MSI is identical to today's.
- The packager passes one or more `.wxs` files; they are compiled and linked into the MSI together with the generated template.
- The contents are installed, upgraded, repaired and removed as part of the product, under the product's normal feature.
- Errors in the fragment are reported as WiX build errors at pack time.

## Shape (insight, not a plan)

- One new pack option (for example `--msiFragment <file.wxs>`, repeatable), mirrored in the MSBuild pack task. The paths are added to the source list passed to `wix build` in `MsiBuilder.CompileWixMsi`.
- WiX only links a fragment when something references it, so the template needs a defined hook. The simplest contract: the fragment defines a `ComponentGroup` with a documented, fixed id, and the template references it from the main feature when the option is set (or the option takes the group id).
- Fragments need stable, documented ids to target: the install folder directory, the main feature and possibly the product's properties. Those ids become a public contract and should not change between versions.
- Fragments that use WiX extensions (util, firewall) need those extensions passed to `wix build`; supporting a small allowed set or an `--msiWixExtension` option is a later step.
- Fragment files may live outside the pack directory; resolve them relative to the current directory, and report a missing file before compiling.
