/// The shared playing-card foundation for flutter_minigames card games.
///
/// Three layers, each usable on its own:
///
///  * **Model** — [Suit], [Rank], [PlayingCard]: immutable, integer-identified,
///    JSON-safe, cheap to sort. Carries the counts every card game reuses
///    ([Rank.pipValue], [Rank.blackjackValue], ace-low/ace-high ordering) and
///    nothing any single game's scoring needs.
///  * **Deck** — [CardDeck] builds and deals a standard 52, and [CardRandom] is
///    a platform-stable seeded shuffle so a deal replays identically on every
///    client. `dart:math`'s `Random` is deliberately not used anywhere.
///  * **Renderer** — [paintPlayingCard] / [paintCardBack] draw a classic card
///    entirely in vectors (no fonts, no assets) with a bounded picture cache,
///    and [CardView] wraps that as a plain widget. [CardGlyphs] and [CardSuits]
///    are exposed for games that need the same rank digits or pips outside a
///    card (counters, badges, tile art).
///
/// A game package depends on this and on `minigames_core`; it never reaches
/// into another game.
library;

export 'src/card_art.dart';
export 'src/card_deck.dart';
export 'src/card_glyphs.dart';
export 'src/card_random.dart';
export 'src/card_suits.dart';
export 'src/card_view.dart';
export 'src/playing_card.dart';
