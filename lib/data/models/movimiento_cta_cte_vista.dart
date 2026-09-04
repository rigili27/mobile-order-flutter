import '../../core/database/sync_state_database_helper.dart';
import 'cobranza.dart';
import 'cuenta_corriente_movimiento.dart';

/// De dónde sale una fila del listado de cuenta corriente de la app.
enum MovimientoOrigen { pedido, manual, cobranza }

/// Estado de una cobranza local respecto del ERP (solo aplica a
/// `MovimientoOrigen.cobranza`).
///
/// - [pendienteSubir]: todavía no se subió (sin conexión / con error).
/// - [sinConfirmar]: subida OK, el ERP la tiene como Receipt en Borrador.
/// - [confirmada]: el admin la confirmó (ya impacta el saldo del catálogo).
enum EstadoCobranzaSync { pendienteSubir, sinConfirmar, confirmada }

/// Fila unificada para el módulo cuenta corriente en modo API: combina los
/// `PedMCCte` locales con las cobranzas registradas desde la app
/// (`cobranza_local`), incluso las que el ERP todavía no confirmó.
class MovimientoCtaCteVista {
  final MovimientoOrigen origen;
  final int codCliente;
  final double importe; // negativo = debe, positivo = haber
  final String? fecha;
  final int? idPedido;
  final String? clienteNombre;

  // Solo cobranzas
  final CobranzaFormaPago? formaPago;
  final EstadoCobranzaSync? estadoSync;

  const MovimientoCtaCteVista({
    required this.origen,
    required this.codCliente,
    required this.importe,
    this.fecha,
    this.idPedido,
    this.clienteNombre,
    this.formaPago,
    this.estadoSync,
  });

  bool get esCobranzaNoConfirmada =>
      origen == MovimientoOrigen.cobranza &&
      estadoSync != EstadoCobranzaSync.confirmada;

  factory MovimientoCtaCteVista.dePedMcCte(CuentaCorrienteMovimiento m) =>
      MovimientoCtaCteVista(
        origen: m.idPedMovil != null
            ? MovimientoOrigen.pedido
            : MovimientoOrigen.manual,
        codCliente: m.codCliente,
        importe: m.importe,
        fecha: m.pedidoFecha,
        idPedido: m.idPedMovil,
        clienteNombre: m.clienteNombre,
      );

  factory MovimientoCtaCteVista.deCobranza(
    Cobranza c,
    OutboxEstado? estadoOutbox,
  ) =>
      MovimientoCtaCteVista(
        origen: MovimientoOrigen.cobranza,
        codCliente: c.codCliente,
        importe: c.importe.abs(), // una cobranza siempre suma (haber)
        fecha: c.fecha,
        formaPago: c.formaPago,
        estadoSync: switch (estadoOutbox) {
          OutboxEstado.sincronizado => EstadoCobranzaSync.sinConfirmar,
          _ => EstadoCobranzaSync.pendienteSubir,
        },
      );
}
