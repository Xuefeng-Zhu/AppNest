import 'package:appnest_client/appnest_client.dart';
import 'package:serverpod_auth_idp_flutter/serverpod_auth_idp_flutter.dart';
import 'package:serverpod_flutter/serverpod_flutter.dart';

// When you are running the app on a physical device, you need to set the
// server URL to the IP address of your computer. You can find the IP
// address by running `ipconfig` on Windows or `ifconfig` on Mac/Linux.
//
// You can set the variable when running or building your app like this:
// E.g. `flutter run --dart-define=SERVER_URL=https://api.example.com/`.
//
// Otherwise, the server URL is fetched from the assets/config.json file or
// defaults to http://$localhost:8080/ if not found.
final serverUrl = getServerUrl();

/// Sets up a global client object that can be used to talk to the server from
/// anywhere in our app. The client is generated from your server code
/// and is set up to connect to a Serverpod running on a local server on
/// the default port. You will need to modify this to connect to staging or
/// production servers.
/// In a larger app, you may want to use the dependency injection of your choice
/// instead of using a global client object. This is just a simple example.
late final Client client;

final _initialization = ClientInitialization(() async {
  client = Client(await serverUrl)
    ..connectivityMonitor = FlutterConnectivityMonitor()
    ..authSessionManager = FlutterAuthSessionManager();
  return client.auth;
});

Future<void> initializeClient() => _initialization.initialize();

/// Creates the transport and restores storage once; retry only revalidates the
/// same session. SDK initialization has a two-second validation deadline whose
/// raw TimeoutException escapes its network-error handling on authenticated web
/// reloads. Allow both Cloud refresh and status requests their normal deadlines.
class ClientInitialization {
  ClientInitialization(
    this.createSessionManager, {
    this.validationTimeout = const Duration(seconds: 45),
  });

  final Future<FlutterAuthSessionManager> Function() createSessionManager;
  final Duration validationTimeout;
  FlutterAuthSessionManager? _auth;
  bool _restored = false;
  Future<void>? _pending;

  Future<void> initialize() =>
      _pending ??= _initialize().whenComplete(() => _pending = null);

  Future<void> _initialize() async {
    final auth = _auth ??= await createSessionManager();
    if (!_restored) {
      await auth.restore();
      _restored = true;
    }
    await auth.validateAuthentication(timeout: validationTimeout);
  }
}
