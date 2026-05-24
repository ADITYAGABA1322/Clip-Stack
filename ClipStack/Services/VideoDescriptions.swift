//
//  VideoDescriptions.swift
//  ClipStack
//
//  Created by Aditya Gaba on 5/23/26.
//

enum VideoDescriptions {
    static func text(for video: Video) -> String {
        map[video.id] ?? "A quiet visual moment captured in motion."
    }

    private static let map: [Int: String] = [
        11187395: "Embers drift upward as flames breathe through the dark.",
        9348931:  "A single flame holds its shape against pure black.",
        9668305:  "Color bleeds and blooms in a slow abstract reverie.",
        4057877:  "Strength builds rep by rep inside the rhythm of the gym.",
        5975953:  "The sky burns softly before the last light slips away.",
        4179958:  "Two kangaroos graze peacefully in the afternoon light.",
        10449906: "People move through glass and steel like a city tide.",
        10004682: "Signs and symbols scatter across white in playful motion.",
        7108918:  "A blank wall becomes a mural one spray at a time.",
        9755176:  "Water carves through forest stone with patient force.",
        13243682: "Smoke rises and unravels like a thought in slow motion.",
        20755400: "Travelers climb through the city, luggage in hand.",
        18516189: "Footsteps and facades turn a busy street into rhythm.",
        18516187: "A green awning frames the street as people pass below.",
        20601705: "Dusk washes the street in amber as the crowd moves on.",
        24818388: "A hidden waterfall cuts cool movement through deep green.",
        36407092: "High-rises hold the last blue light of the evening.",
        18201427: "A deer pauses near the road as the forest waits.",
        34994456: "Snow falls through the winter trees in soft silence.",
        34464347: "A squirrel climbs through branches brushed with autumn color.",
        27604262: "Alpine air, bright water, and mountain calm meet in Trento.",
        34719445: "Rain taps gently on leaves already turning gold.",
        32062161: "A cable car glides above Mexico City with effortless calm.",
        36431226: "Traditional steps turn an outdoor gathering into living rhythm.",
        36014878: "Every movement lands with focus, breath, and intention.",
    ]
}
