/// A launch reservation hands ownership to the player when its State starts.
/// Closing an older route cannot release the replacement player's browser UI.
class BrowserPlayerOwnership {
  Object? _owner;

  bool update(bool active, {Object? owner}) {
    if (!active && owner != null && !identical(owner, _owner)) return false;
    _owner = active ? owner : null;
    return true;
  }
}
