/// Generation tokens for async work whose answer may arrive after the user
/// has moved on.
///
/// Every operation takes a token when it starts ([next]) and checks it after
/// each `await`. Starting the next operation, or [invalidate] (closing the
/// screen it belonged to), makes every earlier token stale, so a late answer
/// is dropped instead of overwriting newer state.
class RequestGeneration {
  int _value = 0;

  /// Starts a new operation; every earlier token becomes stale.
  RequestToken next() => RequestToken._(this, ++_value);

  /// A token for the current generation that does not supersede anything:
  /// for work that should be cancelled by the next [next] or [invalidate],
  /// but must not itself cancel an operation already running.
  RequestToken get current => RequestToken._(this, _value);

  /// Makes every outstanding token stale.
  void invalidate() => ++_value;
}

class RequestToken {
  const RequestToken._(this._owner, this._id);

  final RequestGeneration _owner;
  final int _id;

  /// Whether no newer operation started and nothing invalidated this one.
  bool get isCurrent => _owner._value == _id;
  bool get isStale => !isCurrent;
}

/// Runs a task and hands back its result only if no newer task was started
/// in the meantime: the latest request wins.
class Latest<T> {
  final _generation = RequestGeneration();

  /// Completes with the task's result, or `null` when a newer [run] (or
  /// [cancel]) superseded it. Errors from a superseded task are swallowed;
  /// errors from the latest task are rethrown.
  Future<T?> run(Future<T> Function(RequestToken token) task) async {
    final token = _generation.next();
    try {
      final value = await task(token);
      return token.isCurrent ? value : null;
    } catch (_) {
      if (token.isCurrent) rethrow;
      return null;
    }
  }

  /// Supersedes the task in flight, if any.
  void cancel() => _generation.invalidate();
}
