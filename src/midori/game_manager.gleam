import gleam/otp/actor
import gleam/dict.{type Dict}
import gleam/list
import gleam/int
import gleam/erlang/process.{type Subject}
import move.{type Move}
import game_server.{type Message, new_game_from_fen}
import ids/uuid
import midori/uci_move.{type UciMove}

pub type GameManagerMessage {
  Shutdown
  ApplyMove(reply_with: Subject(ApplyMoveResult), id: String, move: UciMove)
  NewGame(reply_with: Subject(String))
}

pub type ApplyMoveResult {
  ApplyMoveResult(legal_moves: List(Move), fen: String)
}

fn handle_message(
  message: GameManagerMessage,
  game_map: Dict(String, Subject(Message)),
) -> actor.Next(GameManagerMessage, Dict(String, Subject(Message))) {
  case message {
    Shutdown -> actor.Stop(process.Normal)
    ApplyMove(client, id, move) -> {
      let assert Ok(server) = dict.get(game_map, id)
      game_server.apply_move_uci_string(server, move.move)
      let legal_moves = game_server.all_legal_moves(server)
      let length = list.length(legal_moves)
      let random_index = int.random(length)
      let assert Ok(random_move) = list.at(legal_moves, random_index)
      game_server.apply_move(server, random_move)

      let response =
        ApplyMoveResult(
          legal_moves: game_server.all_legal_moves(server),
          fen: game_server.get_fen(server),
        )
      process.send(client, response)
      actor.continue(game_map)
    }
    NewGame(client) -> {
      let server: Subject(Message) = game_server.new_server()
      new_game_from_fen(
        server,
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
      )
      let assert Ok(id) = uuid.generate_v7()
      let game_map = dict.insert(game_map, id, server)
      process.send(client, id)
      actor.continue(game_map)
    }
  }
}

pub fn start_game_manager() {
  let game_map = dict.new()
  let actor = actor.start(game_map, handle_message)
  actor
}
