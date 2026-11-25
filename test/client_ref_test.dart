import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiosco_app/services/client_ref.dart';

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  group('newClientRef', () {
    test('devuelve un UUID v4 valido', () {
      final ref = newClientRef();
      expect(ref, matches(_uuidV4));
      expect(ref.length, 36);
    });

    test('dos llamadas seguidas no colisionan', () {
      final refs = {for (var i = 0; i < 500; i++) newClientRef()};
      expect(refs, hasLength(500));
    });

    test('con un Random sembrado es determinista', () {
      final a = newClientRef(Random(7));
      final b = newClientRef(Random(7));
      expect(a, b);
    });
  });

  group('cartSignature', () {
    test('no depende del orden de los items', () {
      final a = [
        {'id': 'p1', 'quantity': 2},
        {'id': 'p2', 'quantity': 1},
      ];
      final b = [
        {'id': 'p2', 'quantity': 1},
        {'id': 'p1', 'quantity': 2},
      ];
      expect(cartSignature(a), cartSignature(b));
    });

    test('cambia si cambia una cantidad', () {
      final a = [
        {'id': 'p1', 'quantity': 2},
      ];
      final b = [
        {'id': 'p1', 'quantity': 3},
      ];
      expect(cartSignature(a), isNot(cartSignature(b)));
    });

    test('cambia si cambia un producto', () {
      final a = [
        {'id': 'p1', 'quantity': 2},
      ];
      final b = [
        {'id': 'p2', 'quantity': 2},
      ];
      expect(cartSignature(a), isNot(cartSignature(b)));
    });

    test('el carrito vacio tiene una huella estable', () {
      expect(cartSignature([]), '');
      expect(cartSignature([]), cartSignature(const []));
    });
  });
}
