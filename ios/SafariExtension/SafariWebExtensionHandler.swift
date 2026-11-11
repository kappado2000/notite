import SafariServices

/// Extensia Safari a Notițe (parolele pe site-uri). Toată logica e în
/// JavaScript (Resources/, aceeași ca extensia de Chrome); partea nativă doar
/// răspunde la mesajele (neutilizate acum) de la extensie.
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
  func beginRequest(with context: NSExtensionContext) {
    let response = NSExtensionItem()
    response.userInfo = [SFExtensionMessageKey: ["ok": true]]
    context.completeRequest(returningItems: [response], completionHandler: nil)
  }
}
