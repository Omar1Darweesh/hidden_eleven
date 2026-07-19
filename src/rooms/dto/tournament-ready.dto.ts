// Client sends this when a player presses Ready for their current-round match.
// No fields — the server identifies the player via @ConnectedSocket(). It must
// still be a decorated class (not an inline type) because this gateway applies
// its ValidationPipe at the class level with `forbidNonWhitelisted: true`, so
// any payload carrying unexpected fields is correctly rejected.
export class TournamentReadyDto {}
