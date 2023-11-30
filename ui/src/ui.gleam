import position.{Position, to_int}
import rank.{Four, One, Three, Two}
import file.{A, B, C, D, E, F, G, H}
import types.{type MoveData, White}
import config.{type Config, Config, Moveable}
import gleam/option.{Some}
import lustre.{application}
import gchessboard.{Set, init, update, view}

@external(javascript, "./ffi.js", "alert_js")
pub fn alert_js(message: Int) -> Nil

pub fn main() {
  let app = application(init, update, view)
  let assert Ok(interface) = lustre.start(app, "[data-lustre-app]", Nil)

  let after = fn(move_data) {
    let move_data: MoveData = move_data
    let from = move_data.from
    alert_js(to_int(from))
    Nil
  }

  let config =
    Config(moveable: Some(Moveable(
      player: Some(White),
      after: Some(after),
      moves: Some(types.Moves(moves: [
        #(
          types.Origin(origin: Position(file: B, rank: One)),
          types.Destinations(destinations: [
            Position(file: A, rank: Three),
            Position(file: C, rank: Three),
          ]),
        ),
        #(
          types.Origin(origin: Position(file: G, rank: One)),
          types.Destinations(destinations: [
            Position(file: F, rank: Three),
            Position(file: H, rank: Three),
          ]),
        ),
        #(
          types.Origin(origin: Position(file: A, rank: Two)),
          types.Destinations(destinations: [
            Position(file: A, rank: Three),
            Position(file: A, rank: Four),
          ]),
        ),
        #(
          types.Origin(origin: Position(file: B, rank: Two)),
          types.Destinations(destinations: [
            Position(file: B, rank: Three),
            Position(file: B, rank: Four),
          ]),
        ),
        #(
          types.Origin(origin: Position(file: C, rank: Two)),
          types.Destinations(destinations: [
            Position(file: C, rank: Three),
            Position(file: C, rank: Four),
          ]),
        ),
        #(
          types.Origin(origin: Position(file: D, rank: Two)),
          types.Destinations(destinations: [
            Position(file: D, rank: Three),
            Position(file: D, rank: Four),
          ]),
        ),
        #(
          types.Origin(origin: Position(file: E, rank: Two)),
          types.Destinations(destinations: [
            Position(file: E, rank: Three),
            Position(file: E, rank: Four),
          ]),
        ),
        #(
          types.Origin(origin: Position(file: F, rank: Two)),
          types.Destinations(destinations: [
            Position(file: F, rank: Three),
            Position(file: F, rank: Four),
          ]),
        ),
        #(
          types.Origin(origin: Position(file: G, rank: Two)),
          types.Destinations(destinations: [
            Position(file: G, rank: Three),
            Position(file: G, rank: Four),
          ]),
        ),
        #(
          types.Origin(origin: Position(file: H, rank: Two)),
          types.Destinations(destinations: [
            Position(file: H, rank: Three),
            Position(file: H, rank: Four),
          ]),
        ),
      ])),
    )))

  interface(Set(config))

  Nil
}
