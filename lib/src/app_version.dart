/// Immutable semantic version (`major.minor.patch`) with tolerant parsing.
///
/// Kept dependency-free and self-contained so the whole module stays portable
/// across apps. Build metadata (anything after `+`) is intentionally ignored,
/// because store/version-name comparisons only care about the release number.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// Matches a dotted version core: `major.minor` or `major.minor.patch`.
  static final RegExp _dottedVersion = RegExp(r'\d+\.\d+(?:\.\d+)?');

  /// Matches a string that is nothing but a bare major version (e.g. `2`).
  static final RegExp _bareMajor = RegExp(r'^\d+$');

  /// Extracts the version from wherever it sits in the string.
  ///
  /// The App Store lookup API returns the marketing version verbatim, and
  /// developers sometimes decorate it with the build number or a label —
  /// before or after the version (`1.4.9 (149)`, `149 1.4.9`, `v1.4.9`,
  /// `release 1.4.9 build 149`). The rules:
  ///
  /// - Exactly one dotted version (`x.y` / `x.y.z`) in the string → use it,
  ///   ignore everything around it. A missing patch defaults to `0`.
  /// - Two or more dotted versions → ambiguous → `null` (callers fail open,
  ///   so a bad string can never force or lock users).
  /// - No dotted version → only a pure bare integer (`2`) is accepted, as
  ///   `major.0.0`. Everything else → `null`.
  static AppVersion? tryParse(String? raw) {
    if (raw == null) return null;
    final input = raw.trim();
    if (input.isEmpty) return null;

    final dotted = _dottedVersion.allMatches(input).toList();
    if (dotted.length > 1) return null;

    final core = dotted.isNotEmpty
        ? dotted.first.group(0)!
        : (_bareMajor.hasMatch(input) ? input : null);
    if (core == null) return null;

    final numbers = core.split('.').map(int.tryParse).toList();
    if (numbers.any((n) => n == null)) return null;
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return AppVersion(numbers[0]!, numbers[1]!, numbers[2]!);
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
