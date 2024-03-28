import gleam/otp/actor
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import move.{type Move}
import game_server.{type Message, apply_move, new_game_from_fen}
import ids/uuid

pub type GameManagerMessage(element) {
  Shutdown
  ApplyMove(reply_with: Subject(List(Move)), uuid: String, move: Move)
  NewGame(reply_with: Subject(String))
}

fn handle_message(
  message: GameManagerMessage(e),
  game_map: Dict(String, Subject(Message)),
) -> actor.Next(GameManagerMessage(e), Dict(String, Subject(Message))) {
  case message {
    Shutdown -> actor.Stop(process.Normal)
    ApplyMove(_client, uuid, move) -> {
      let assert Ok(server) = dict.get(game_map, uuid)
      apply_move(server, move)
      actor.continue(game_map)
    }
    NewGame(client) -> {
      let server: Subject(Message) = game_server.new_server()
      new_game_from_fen(
        server,
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
      )
      let assert Ok(id) = uuid.generate_v7()
      dict.insert(game_map, id, server)
      process.send(client, id)
      actor.continue(game_map)
    }
  }
}

pub fn new_manager() {
  let game_map = dict.new()
  let assert Ok(actor) = actor.start(game_map, handle_message)
  actor
}
