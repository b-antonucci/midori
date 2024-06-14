import gleam/erlang/process.{type Subject}
import midori/types.{type UserColor}
import midori/uci_move.{type UciMove}
import move.{type Move}
import status.{type Status}

pub type GameManagerMessage {
  Shutdown
  ApplyMove(
    reply_with: Subject(Result(ApplyMoveResult, String)),
    game_id: String,
    user_id: String,
    move: UciMove,
  )
  // TODO: This should be sync call, NOTICE: many/all of the messages should be sync
  // if only to get confirmation that the message was received
  ApplyAiMove(game_id: String, user_id: String, move: String)
  // TODO: rename this to NewComputerGame or something like that
  NewGame(reply_with: Subject(Result(String, String)), user_color: UserColor)
  RemoveGame(reply_with: Subject(Result(Nil, Nil)), id: String)
  GetGameInfo(reply_with: Subject(Result(GameInfo, String)), id: String)
}

pub type ApplyMoveResult {
  ConfirmMove(move: UciMove)
}

pub type GameInfo {
  GameInfo(
    fen: String,
    status: Status,
    moves: List(Move),
    user_color: UserColor,
  )
}
