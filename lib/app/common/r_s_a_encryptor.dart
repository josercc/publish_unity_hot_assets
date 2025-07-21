import 'package:encrypt/encrypt.dart';
import 'package:pointycastle/asymmetric/api.dart';

Future<String> encryptRSA(String plainText, String publicKeyText) async {
  final publicKey = RSAKeyParser().parse(publicKeyText) as RSAPublicKey;
  final encrypter = Encrypter(RSA(publicKey: publicKey));
  final encrypted = encrypter.encrypt(plainText);
  return encrypted.base64;
}
