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

export 'card_art.dart';
export 'card_deck.dart';
export 'card_glyphs.dart';
export 'card_random.dart';
export 'card_suits.dart';
export 'card_view.dart';
export 'playing_card.dart';
