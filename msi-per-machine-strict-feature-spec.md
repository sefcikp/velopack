# Feature spec: strict per-machine MSI

## Purpose

Offer an MSI that can only be installed per-machine, into one fixed location under Program Files. `--instLocation PerMachine` already sets the package scope, but the install can still be changed from the command line: a per-user install can be forced with `ALLUSERS=""` or `MSIINSTALLPERUSER=1`, and the folder can be redirected with `VELOPACK_INSTALLDIR` or by setting the public `INSTALLFOLDER` property.

## Supported use case

Managed environments (schools, enterprises) where IT deploys one machine-wide install that every user on the machine runs, and where the vendor needs guarantees about it:
- The install folder is only writable by administrators and SYSTEM, which matters when a privileged component (for example an update service) later acts on that folder. A folder chosen on a user-writable drive would inherit permissions that let ordinary users modify files that other users and administrators run.
- Support and tooling can rely on a single known location.
- Fewer installer parameters to document and to get wrong.

## Behaviour

- Opt-in; existing `PerUser` / `PerMachine` / `Either` behaviour stays unchanged.
- The install refuses to proceed unless it is an elevated per-machine install; overriding the scope from the command line fails with a clear message.
- The install folder is always `Program Files\{publisher}\{title}` (the per-machine default). No dialog, property or command-line value can change it.
- Upgrade, repair and uninstall keep resolving the folder from the installed product, as today.

## Shape (insight, not a plan)

- Either a new value of the install-location option or a separate flag (for example `--msiStrictPerMachine`) that is only valid with `PerMachine`. A separate flag is probably easier to argue upstream.
- In the MSI template, conditioned on the flag:
  - a launch condition on `Privileged`, `ALLUSERS=1` and `NOT MSIINSTALLPERUSER`;
  - no `VELOPACK_INSTALLDIR` property and none of the steps that apply it;
  - the install folder no longer settable from outside, either by giving the directory a private (not all-uppercase) id or by always setting it to the default before `CostFinalize` on first install. The id is referenced in many places, including the custom-action data passed to the Rust DLL, so changing it touches the whole template.
- Optionally, explicit permissions on the install folder (administrators and SYSTEM full control, users read and execute, no inheritance) as defense in depth.
- If an additional-fragment feature exists, the directory id that fragments reference must stay stable and documented.
