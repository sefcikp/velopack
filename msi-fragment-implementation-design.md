# MSI fragment implementation design

Status: implemented on `feat/msi-fragment`; broader lifecycle validation remains outstanding. CLI tests and a real MSI component-linkage test pass. MSBuild task verification is limited by existing project build errors and unavailable declared target prerequisites.

## Public contract

Add repeatable `--msiFragment <file.wxs>` to Windows `vpk pack`:

```text
vpk pack --packId Example.App --packVersion 1.0.0 --packDir publish --msi --msiFragment installer/root.wxs --msiFragment installer/components.wxs
```

Expose `string[] MsiFragments` (empty by default) on `WindowsPackCommand`, `WindowsPackOptions`, and the MSBuild `PackTask`. Use the existing array-option pattern used by `--header`; verify repeated occurrences accumulate, and require a value for every occurrence. Preserve separate paths, including spaces; do not split CLI values on commas or semicolons.

Across the supplied source files, define exactly one public `ComponentGroup` named `VelopackMsiComponents`. It may contain components directly and/or reference other component groups defined in any supplied source. Multiple inputs do not each define the fixed group. WiX reports missing groups, duplicate definitions, malformed XML, unresolved references, and unsupported extension elements.

The option requires `--msi` / `BuildMsi=true`; reject misuse rather than silently ignoring the files. Existing MSI options and defaults remain unchanged. No automatic elevation, install-scope change, extension loading, source scanning for group ids, or template replacement is added.

## Linking and stable identifiers

The current template has package-level `Files` harvesting and no explicit `Feature`. Preserve WiX's implicit feature. Conditionally insert this directly under `Package`, adjacent to `Files`:

```xml
<ComponentGroupRef Id="VelopackMsiComponents"/>
```

WiX permits `ComponentGroupRef` under `Package` and supplies a default feature when no features are authored. This avoids introducing an explicit feature that could change how existing components are assigned. Verify with the repository's bundled WiX that both existing and fragment components appear in `FeatureComponents` under the same feature before proceeding with the rest of implementation.

Supported integration points:

| Identifier | Contract |
| --- | --- |
| `VelopackMsiComponents` | Required aggregate component group, referenced only when sources are supplied. |
| `INSTALLFOLDER` | Existing application installation root, usable as a component directory or through `DirectoryRef`. |

Do not promise a concrete main-feature id: the aggregate group is the supported way to join it. Fragments must not author their own `Package`, `Feature`, or `FeatureRef`, or replace existing Velopack symbols. This is an authoring contract, not a new XML validator. `CURRENTFOLDER` exists only in no-stub mode and harvested ids are generated; neither is a public extension point. No additional application properties or preprocessor variables are exposed in this iteration.

This deliberately narrows the spec's suggested stable-feature-id surface: consumers can join the normal feature without depending on its implementation id.

## Input validation and path handling

In `WindowsPackOptionsValidator`, validate each supplied entry: nonblank, valid path, existing regular file, and `.wxs` extension (case-insensitive). Report the offending entry before packaging/compilation. Reject fragments when `BuildMsi` is false. Null and empty arrays both mean disabled for programmatic callers.

Resolve paths to absolute paths against the invocation working directory before invoking WiX. Do not resolve against `PackDirectory`, stage/copy fragment sources, or change the compiler working directory. Preserve input order and remove duplicate normalized paths using Windows case-insensitive comparison so a repeated source is not compiled twice. Do not swallow read failures or fabricate success if a file disappears after validation.

Inside authoring, use `$(sys.SOURCEFILEDIR)` for adjacent assets and includes rather than depending on the pack directory. This works because original source paths are passed to WiX. Bare relative asset paths retain WiX's existing resolution behavior; adding global bind paths is out of scope.

## Code changes

| File | Change |
| --- | --- |
| `src/vpk/Velopack.Vpk/Commands/Packaging/WindowsPackCommand.cs` | Add the array property and Windows MSI option with help describing the fixed group and `--msi` requirement. |
| `src/vpk/Velopack.Packaging.Windows/Commands/WindowsPackOptions.cs` | Add the matching array property. |
| `src/vpk/Velopack.Packaging.Windows/Commands/WindowsPackOptionsValidator.cs` | Add per-entry and cross-option validation shared by CLI and MSBuild. |
| `src/vpk/Velopack.Build/PackTask.cs` | Add `string[] MsiFragments` for direct task use. |
| `src/vpk/Velopack.Vpk/OptionMapper.cs`, `src/vpk/Velopack.Build/TaskOptionsMapper.cs` | Verify Mapperly propagates the matching array property; add explicit mapping only if needed. |
| `src/vpk/Velopack.Packaging.Windows/Msi/MsiTemplateData.cs` | Add normalized `MsiFragments` and derived `HasMsiFragments`. |
| `src/vpk/Velopack.Packaging.Windows/Msi/MsiBuilder.cs` | Populate normalized paths in `ConvertOptionsToTemplateData`; append them to the existing template/dialog source list in `CompileWixMsi`. Quote each source as a separate argument using the existing hosted-command convention. |
| `src/vpk/Velopack.Packaging.Windows/Msi/Templates/MsiTemplate.hbs` | Add the conditional package-level group reference. |

Keep `CompileWixMsi`'s public signature unchanged. With no fragments, preserve the old source list and rendered authoring, including whitespace where practical. Use a false conditional whose removal leaves the original template intact. Compatibility means equivalent authored MSI behavior, not byte-identical MSI binaries across independent builds.

MSBuild callers pass `MsiFragments="@(VelopackMsiFragment->'%(FullPath)')"` to `PackTask`, with items declared relative to the project. Keep task-relative paths consistent with the documented current-directory rule; using item FullPath avoids dependence on the MSBuild process directory. The existing `Velopack.Build.targets` invokes `PackTask` but does not wire `BuildMsi`. Add both `BuildMsi="$(VelopackBuildMsi)"` and the fragment item transform to that invocation, defaulting `VelopackBuildMsi` to `false` when unset. This wiring is necessary for publish-driven fragment use; leave other missing MSI properties outside this change. Document project usage with `<VelopackBuildMsi>true</VelopackBuildMsi>` and `<VelopackMsiFragment Include="installer/root.wxs"/>`, and cover the target-to-task wiring in the MSBuild validation.

The existing compiler failure propagation and post-build MSI signing remain in place. Do not catch WiX errors merely to replace their source locations and diagnostic codes with a generic fragment error.

## Authoring example

This example uses no extensions and installs a registry value in the selected install context:

```xml
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Fragment>
    <ComponentGroup Id="VelopackMsiComponents">
      <ComponentRef Id="ExampleRegistration"/>
    </ComponentGroup>
    <DirectoryRef Id="INSTALLFOLDER">
      <Component Id="ExampleRegistration" Guid="*">
        <RegistryValue Root="HKMU" Key="Software\Example.App"
                       Name="Installed" Type="integer" Value="1" KeyPath="yes"/>
      </Component>
    </DirectoryRef>
  </Fragment>
</Wix>
```

For multiple files, replace or supplement `ComponentRef` with `ComponentGroupRef` entries, and define those groups in other supplied files. All needed source files must be listed explicitly.

## Ownership and lifecycle boundaries

Fragment resources follow Windows Installer component rules. Authors own stable component identity, appropriate key paths, upgrade compatibility, scope, and rollback-safe custom actions. Machine-only resources such as services require a suitable per-machine install configuration; this option does not enforce the separate strict per-machine feature.

The template harvests the entire portable payload. A fragment must not install a second copy of the same target file under another component or depend on generated harvested file ids. For an MSI-owned service, keep its executable outside the app payload and author it in a separate component, for example under a dedicated subdirectory of `INSTALLFOLDER`. Reference build assets with `$(sys.SOURCEFILEDIR)`. Fragment-only assets do not automatically enter the portable ZIP, Setup.exe, or update packages and do not pass through the existing app-payload signing stage; sign service binaries before supplying them.

In-app updates do not execute MSI fragment lifecycle work. Keep MSI-owned service payload outside `current` and `packages`, and upgrade it through an MSI. Existing Velopack cleanup removes the application root on uninstall; do not advertise preservation of arbitrary data under that root. Adding support to decorate already harvested components or exclude files from harvesting is a separate feature.

WiX extension selection/loading remains deferred. Registry resources, basic files, and core service authoring are in scope; firewall/util authoring requiring extensions is not supported by this first iteration. Native custom action and Rust changes are unnecessary.

## Validation plan

1. **First implementation check:** compile a minimal fixture with the package-level reference using bundled WiX. Inspect `Feature`, `FeatureComponents`, and `Component` tables to prove existing and added components share the existing feature. Do not ship based only on template string assertions.
2. **CLI and shared validation:** absent, one, and repeated sources; CLI-to-options mapping; missing argument; whitespace; wrong extension; missing file; directory input; mixed-case `.WXS`; paths with spaces and outside the pack directory; fragments without `--msi`. Exercise shared validation directly to cover MSBuild/programmatic callers.
3. **Mapping and template:** MSBuild array mapping; normalized paths and deduplication; exactly one reference when enabled and none when disabled; compare disabled rendering against the pre-change template using identical data.
4. **Windows build integration:** compile single-file and split-group fixtures, including an adjacent payload located using `SOURCEFILEDIR`. Inspect MSI tables for the added registry/file rows and their feature membership. Verify all baseline app components remain. Confirm missing aggregate group, duplicate symbols, invalid XML, and missing referenced payload produce actionable WiX failures.
5. **Lifecycle integration:** extend the existing per-user MSI test harness with a unique HKCU registry resource and an MSI-owned test file outside `current`. Install, remove the resource/file, repair, upgrade to a second MSI version, and uninstall; assert restoration, new content, and cleanup. Force an install failure after resources are written in a dedicated fixture and verify rollback removes them. Use unique test ids and existing cleanup patterns. Service installation/start/stop/uninstall needs a separate explicitly elevated test in a disposable Windows environment.
6. **Compatibility:** run existing MSI packaging tests and Windows command tests in Debug, sequentially. Check that supplying fragments does not add resources to non-MSI outputs. Test standalone on `feat/msi-fragment`; later integration with the UpgradeCode and strict per-machine branches must not be a prerequisite.

Use the repository's xUnit v3 filtering syntax, for example `dotnet test --project test/Velopack.Packaging.Tests -- --filter-class "*MsiTests"`. No builds or tests are required merely to review this design; implementation must complete the above checks before claiming the feature works.

## References

- [WiX ComponentGroupRef schema](https://docs.firegiant.com/wix/schema/wxs/componentgroupref/) lists Package as a supported parent.
- [WiX default feature behavior](https://docs.firegiant.com/wix/whatsnew/#default-feature) describes automatic component assignment when no explicit features are authored.
- [WiX preprocessor variables](https://docs.firegiant.com/wix/tools/preprocessor/) documents `SOURCEFILEDIR` and its trailing directory separator.
