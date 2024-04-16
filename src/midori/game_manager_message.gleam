import gleam/erlang/process.{type Subject}
import midori/uci_move.{type UciMove}

pub type GameManagerMessage {
  Shutdown
  ApplyMove(reply_with: Subject(ApplyMoveResult), id: String, move: UciMove)
  // TODO: This should be sync call, NOTICE: many/all of the messages should be sync
  // if only to get confirmation that the message was received
  ApplyAiMove(id: String, move: String)
  NewGame(reply_with: Subject(String))
  RemoveGame(reply_with: Subject(Result(Nil, Nil)), id: String)
}

pub type ApplyMoveResult {
  ConfirmMove(move: UciMove)
}
