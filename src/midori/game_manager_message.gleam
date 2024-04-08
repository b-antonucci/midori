import gleam/erlang/process.{type Subject}
import midori/uci_move.{type UciMove}

pub type GameManagerMessage {
  Shutdown
  ApplyMove(reply_with: Subject(ApplyMoveResult), id: String, move: UciMove)
  ApplyAiMove(id: String, move: String)
  NewGame(reply_with: Subject(String))
}

pub type ApplyMoveResult {
  ConfirmMove(move: UciMove)
}
