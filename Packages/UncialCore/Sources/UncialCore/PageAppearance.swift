/// Whether a page follows the light or dark appearance of the view it is shown in (`system`) or is
/// always light or always dark: the app's Appearance setting, which the Quick Look extension applies
/// to its pages because it cannot set the appearance of Quick Look's window.
public enum PageAppearance: String, CaseIterable, Sendable {
    case system, light, dark
}
