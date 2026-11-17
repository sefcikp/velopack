# Feature spec: explicit MSI UpgradeCode

## Purpose

Let the packager set the MSI `UpgradeCode` explicitly. Today `vpk pack --msi` always derives it from the pack id (`GuidUtil.CreateGuidFromHash("{packId}:UpgradeCode")`), so a Velopack MSI can never take over an existing MSI product line.

## Supported use case

An application already ships an MSI built with another toolchain (for example a hand-written WiX project). The vendor moves to Velopack's MSI and wants installs of the old MSI to be major-upgraded in place: same product line in Apps & Features, the old version removed by Windows Installer, deployment tools (Group Policy, Intune, SCCM) treating it as a new version of the same product rather than a second product.

Secondary use cases:
- Changing the pack id without breaking the upgrade chain of installed MSIs.
- Several pack ids (for example per-channel builds) where the vendor wants full control over which ones upgrade each other.

## Behaviour

- Without the option nothing changes: the derived UpgradeCode stays the default, so existing products keep upgrading.
- With the option, the given GUID is used as the package `UpgradeCode`, so the built-in `MajorUpgrade` finds and removes earlier products with that code.
- Invalid GUIDs are rejected at pack time with a clear error.

## Shape (insight, not a plan)

- One new optional pack option (for example `--msiUpgradeCode <guid>`), next to the other `--msi*` options in the Windows pack command and options, mirrored as a property in the MSBuild pack task.
- `MsiBuilder.ConvertOptionsToTemplateData` uses it instead of the derived value; the template already consumes `UpgradeCodeGuid`.
- Leave `ComponentGenerationSeedGuid` derived from the pack id; it is a separate concern.
- Document the caveats for the take-over case: the new MSI version must be higher than the old product's version (MSI version rules), both products must have the same install scope (per-machine cannot upgrade per-user and vice versa), and the old product's install location and properties do not carry over.
