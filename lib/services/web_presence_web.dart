import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Confirmare cu amprenta / fața / PIN-ul Windows Hello în browser
/// (WebAuthn, autentificatorul calculatorului). La prima folosire creează o
/// cheie de acces locală („Notițe”), apoi doar o verifică. Nu pleacă nimic
/// pe internet: e doar dovada că persoana din fața calculatorului e tu.
const _storageKey = 'notite_hello_credential';

Future<bool> webPresenceAvailable() async {
  try {
    final ok =
        await web
                .PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()
            .toDart;
    return ok.toDart;
  } catch (_) {
    return false;
  }
}

JSUint8Array _random(int n) {
  final r = Random.secure();
  return Uint8List.fromList([for (var i = 0; i < n; i++) r.nextInt(256)]).toJS;
}

Future<bool> webPresenceVerify() async {
  final saved = web.window.localStorage.getItem(_storageKey);
  try {
    if (saved == null) return await _register();
    final id = base64Decode(saved);
    final cred = await web.window.navigator.credentials
        .get(
          web.CredentialRequestOptions(
            publicKey: web.PublicKeyCredentialRequestOptions(
              challenge: _random(32),
              timeout: 60000,
              userVerification: 'required',
              allowCredentials: [
                web.PublicKeyCredentialDescriptor(
                  type: 'public-key',
                  id: id.toJS,
                ),
              ].toJS,
            ),
          ),
        )
        .toDart;
    return cred != null;
  } catch (e) {
    // cheia nu mai există (ștearsă din Windows / alt profil): o refacem
    if ('$e'.contains('NotAllowedError') && saved != null) {
      web.window.localStorage.removeItem(_storageKey);
    }
    return false;
  }
}

Future<bool> _register() async {
  final cred = await web.window.navigator.credentials
      .create(
        web.CredentialCreationOptions(
          publicKey: web.PublicKeyCredentialCreationOptions(
            rp: web.PublicKeyCredentialRpEntity(name: 'Notițe'),
            user: web.PublicKeyCredentialUserEntity(
              name: 'Notițe – Parole',
              displayName: 'Notițe – Parole',
              id: _random(16),
            ),
            challenge: _random(32),
            pubKeyCredParams: [
              web.PublicKeyCredentialParameters(type: 'public-key', alg: -7),
              web.PublicKeyCredentialParameters(type: 'public-key', alg: -257),
            ].toJS,
            timeout: 60000,
            authenticatorSelection: web.AuthenticatorSelectionCriteria(
              authenticatorAttachment: 'platform',
              userVerification: 'required',
              residentKey: 'discouraged',
            ),
          ),
        ),
      )
      .toDart;
  if (cred == null) return false;
  final raw = (cred as web.PublicKeyCredential).rawId.toDart.asUint8List();
  web.window.localStorage.setItem(_storageKey, base64Encode(raw));
  return true;
}
