import Foundation

/// Reads Supabase project config from Info.plist, which is populated from
/// `Secrets.xcconfig` (gitignored — see `Secrets.xcconfig.example`) via
/// `project.yml`'s `info.properties`. Never hardcode real values here.
enum SupabaseConfig {
    static var url: URL? {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let url = URL(string: raw),
            url.scheme != nil,
            !raw.contains("YOUR_PROJECT")
        else {
            return nil
        }
        return url
    }

    static var anonKey: String? {
        guard
            let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            !key.isEmpty,
            key != "your_anon_key_here"
        else {
            return nil
        }
        return key
    }

    /// `true` once `Secrets.xcconfig` has been filled in with real values.
    /// Auth screens use this to show a setup message instead of crashing.
    static var isConfigured: Bool {
        url != nil && anonKey != nil
    }
}
