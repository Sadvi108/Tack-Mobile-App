import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentInteractionControllerDelegate {
  private var documentController: UIDocumentInteractionController?
  private weak var documentPresenter: UIViewController?

  override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TackDocumentOpen") else { return }
    let channel = FlutterMethodChannel(name: "com.tack.app/documents", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "open" else { result(FlutterMethodNotImplemented); return }
      guard let self, let args = call.arguments as? [String: Any], let path = args["path"] as? String,
        let presenter = registrar.viewController else {
        result(FlutterError(code: "open_failed", message: "The document could not be opened.", details: nil)); return
      }
      let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
      let roots = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask) + [URL(fileURLWithPath: NSTemporaryDirectory())]
      guard roots.contains(where: { url.path.hasPrefix($0.appendingPathComponent("tack_documents").resolvingSymlinksInPath().path + "/") }),
        FileManager.default.fileExists(atPath: url.path) else {
        result(FlutterError(code: "open_failed", message: "The document is unavailable.", details: nil)); return
      }
      let controller = UIDocumentInteractionController(url: url)
      controller.delegate = self
      self.documentController = controller
      self.documentPresenter = presenter
      let bounds = presenter.view.bounds
      let anchor = CGRect(x: bounds.midX, y: bounds.maxY - 60, width: 1, height: 1)
      if controller.presentOptionsMenu(from: anchor, in: presenter.view, animated: true) {
        result(nil)
      } else if controller.presentPreview(animated: true) {
        result(nil)
      } else {
        result(FlutterError(code: "no_app", message: "No document reader is available.", details: nil))
      }
    }
  }

  func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
    return documentPresenter ?? UIViewController()
  }
}
