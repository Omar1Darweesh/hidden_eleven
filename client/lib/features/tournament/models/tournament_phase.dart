enum TournamentPhase {
  bracketReveal,
  readyCheck,
  simulating,
  roundResult,
  complete;

  static TournamentPhase fromJson(String value) {
    switch (value) {
      case 'bracket_reveal':
        return TournamentPhase.bracketReveal;
      case 'ready_check':
        return TournamentPhase.readyCheck;
      case 'simulating':
        return TournamentPhase.simulating;
      case 'round_result':
        return TournamentPhase.roundResult;
      case 'complete':
        return TournamentPhase.complete;
      default:
        throw ArgumentError('Unknown TournamentPhase: $value');
    }
  }
}
