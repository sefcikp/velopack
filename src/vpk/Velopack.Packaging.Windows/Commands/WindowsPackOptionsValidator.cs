using FluentValidation;
using Velopack.Core;
using Velopack.Core.Validation;
using Velopack.Windows;

namespace Velopack.Packaging.Windows.Commands;

public sealed class WindowsPackOptionsValidator : PackOptionsValidator<WindowsPackOptions>
{
    public WindowsPackOptionsValidator()
    {
        RuleFor(x => x.EntryExecutableName).MustHaveExtension(".exe");
        RuleFor(x => x.Icon).MustHaveExtension(".ico");
        RuleFor(x => x.SplashImage).MustBeExistingFile();
        RuleFor(x => x.SignParallel).InclusiveBetween(1, 1000);
        RuleFor(x => x.SignExclude).MustBeValidRegex();
        RuleFor(x => x.AzureTrustedSignFile).MustBeExistingFile();
        RuleFor(x => x.MsiFragments)
            .Must((options, paths) => paths == null || paths.Length == 0 || (options.BuildMsi && !options.NoInst))
            .WithMessage("MSI fragments require --msi and cannot be combined with --noInst.");
        RuleForEach(x => x.MsiFragments).Cascade(CascadeMode.Stop)
            .NotEmpty()
            .Must(File.Exists).WithMessage("MSI fragment '{PropertyValue}' must be an existing file.")
            .Must(path => string.Equals(Path.GetExtension(path), ".wxs", StringComparison.OrdinalIgnoreCase))
            .WithMessage("MSI fragment '{PropertyValue}' must have a .wxs extension.");
        RuleFor(x => x.MsiVersionOverride).MustBeValidMsiVersion();
        RuleFor(x => x.MsiUpgradeCode)
            .Must(v => v == null || Guid.TryParseExact(v, "D", out _) || Guid.TryParseExact(v, "B", out _))
            .WithMessage("{PropertyName} must be a hyphenated GUID, with or without braces ('{PropertyValue}').");
        RuleFor(x => x.MsiTopBanner).MustHaveExtension(".bmp");
        RuleFor(x => x.MsiDialogBackground).MustHaveExtension(".bmp");
        RuleFor(x => x.InstWelcome).MustBeExistingFile();
        RuleFor(x => x.InstReadme).MustBeExistingFile();
        RuleFor(x => x.InstLicense).MustBeExistingFile();
        RuleFor(x => x.InstConclusion).MustBeExistingFile();
        RuleFor(x => x.SignTemplate)
            .Must((opt, _) => new[] { opt.SignTemplate, opt.SignParameters, opt.AzureTrustedSignFile }.Count(v => !string.IsNullOrEmpty(v)) <= 1)
            .WithMessage("Cannot use more than one of 'signTemplate', 'signParams' and 'azureTrustedSignFile' options together, please choose one.");
        RuleFor(x => x.Shortcuts)
            .Must(v => string.IsNullOrEmpty(v) || v
                .Split([',', ';'], StringSplitOptions.RemoveEmptyEntries)
                .Select(x => x.Trim())
                .All(x => Enum.TryParse<ShortcutLocation>(x, true, out _)))
            .WithMessage(
                "{PropertyName} contains invalid shortcut locations ('{PropertyValue}'). " +
                $"Valid values for comma delimited list are: {string.Join(", ", Enum.GetNames(typeof(ShortcutLocation)))}.");
        RuleFor(x => x.Runtimes).Custom((v, context) => {
            try {
                WindowsPackCommandRunner.ParseRuntimeDependencies(v);
            } catch (UserInfoException ex) {
                context.AddFailure(ex.Message);
            }
        });
    }
}
