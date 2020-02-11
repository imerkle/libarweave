import 'package:jose/jose.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:libarweave/src/utils.dart';
import 'package:pointycastle/export.dart';

class Wallet {
  JsonWebKey _wallet;
  String _owner;
  String _address;

  Wallet(String jsonWebKey) {
    var jwk = jsonDecode(jsonWebKey);
    _wallet = JsonWebKey.fromJson(jwk);
    _owner = jwk['n'];
    _address = base64Url.encode(sha256
        .convert(base64Url.decode(
            _owner + List.filled((4 - _owner.length % 4) % 4, '=').join()))
        .bytes);
    if (_address.endsWith('=')) {
      _address = _address.substring(0, _address.length - 1);
    }
  }

  void loadWallet(String jsonWebKey) {
    var jwk = jsonDecode(jsonWebKey);
    _wallet = JsonWebKey.fromJson(jwk);
    _owner = jwk['n'];
    _address = base64Url.encode(sha256
        .convert(base64Url.decode(
            _owner + List.filled((4 - _owner.length % 4) % 4, '=').join()))
        .bytes);
    if (_address.endsWith('=')) {
      _address = _address.substring(0, _address.length - 1);
    }
  }

  String get address {
    return _address;
  }

  Future<double> balance() async {
    var response = await getHttp('/wallet/$_address/balance');
    return winstonToAr(response);
  }

  Future<String> lastTransaction() async {
    var response = await getHttp('/wallet/$_address/last_tx');
    return response;
  }

  Future<List> allTransactionsFromAddress() async {
    final response = await getHttp('/wallet/$_address/txs/');
    return jsonDecode(response);
  }

  Future<List> allTransactionsToAddress() async {
    final response = await getHttp('/wallet/$_address/deposits/');
    return jsonDecode(response);
  }

  Future<List> dataTransactionHistory() async {
    final query = {
      'query':
          'query {transactions(from: ["${_address}"]){id tags{name value}}} '
    };
    final response = await postHttp('/arql', jsonEncode(query));
    if (response.body != '') {
      final txns = jsonDecode(response.body)['data']['transactions'];
      return txns;
    }
    return [];
  }

  List<int> signTransaction(String lastTx, String reward,
      {String targetAddress = '',
      List tags,
      String quantity = '0',
      String data = ''}) {
    final dataBytes = decodeBase64EncodedBytes(base64Url.encode(ascii.encode(data)));
    final lastTxBytes = decodeBase64EncodedBytes(lastTx);
    final targetBytes = decodeBase64EncodedBytes(targetAddress);
    final ownerBytes = decodeBase64EncodedBytes(_owner);
    final rewardBytes = utf8.encode(reward);
    final quantityBytes = utf8.encode(quantity);
    var tagsBytes;
    if (tags != null) {
      for (var tag in tags) {
        tagsBytes += decodeBase64EncodedBytes(tag['key']);
        tagsBytes += decodeBase64EncodedBytes(tag['value']);
      }
    } 

    var rawTransaction = ownerBytes +
        targetBytes +
        dataBytes +
        quantityBytes +
        rewardBytes +
        lastTxBytes;

    if (tagsBytes != null){
      rawTransaction += tagsBytes;
    }

    return _wallet.sign(rawTransaction, algorithm: 'RS256');
  }

  dynamic postTransaction(List<int> signature, String lastTx, String reward,
      {String targetAddress = '',
      List tags,
      String quantity = '0',
      String data = ''}) async {
    final digest = SHA3Digest(256, true);
    final hash = digest.process(signature);
    tags = [];
    print('Transaction hash is: $hash');
    final id = encodeBase64EncodedBytes(hash);
    print('Transaction ID is: $id');
    final body = json.encode({
      'id': id,
      'last_tx': lastTx,
      'owner': encodeBase64EncodedBytes(ascii.encode(_owner)),
      'tags': tags,
      'target': encodeBase64EncodedBytes(ascii.encode(targetAddress)),
      'reward': reward,
      'quantity': quantity,
      'data': encodeBase64EncodedBytes(ascii.encode(data)),
      'signature': encodeBase64EncodedBytes(signature)
    });
    final response = await postHttp('/tx', body);
    return response;
  }
}
