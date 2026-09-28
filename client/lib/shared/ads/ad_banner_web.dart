import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';
import 'package:hidden_eleven/shared/ads/ad_config.dart';

int _viewCounter = 0;

/// Renders a real AdSense `<ins class="adsbygoogle">` unit inside an
/// `HtmlElementView`. Each call registers its own platform-view factory
/// (view types must be unique, hence the counter) and pushes the standard
/// `(adsbygoogle = window.adsbygoogle || []).push({})` call once the
/// element is in the DOM, matching AdSense's own embed snippet.
Widget buildAdBannerElement({
  required String slotId,
  required double width,
  required double height,
}) {
  final viewType = 'adsbygoogle-view-${_viewCounter++}';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
    final ins = html.Element.tag('ins')
      ..className = 'adsbygoogle'
      ..style.display = 'inline-block'
      ..style.width = '${width}px'
      ..style.height = '${height}px'
      ..setAttribute('data-ad-client', AdConfig.clientId)
      ..setAttribute('data-ad-slot', slotId);

    // Deferred to a microtask so `ins` is attached to the DOM (the view
    // factory's return value is inserted by the engine right after this
    // callback returns) before adsbygoogle tries to measure/fill it.
    Future.microtask(() {
      try {
        final adsbygoogle = js.context['adsbygoogle'];
        if (adsbygoogle is js.JsArray) {
          adsbygoogle.add(js.JsObject.jsify({}));
        } else {
          js.context['adsbygoogle'] = js.JsArray.from([js.JsObject.jsify({})]);
        }
      } catch (_) {
        // AdSense script not loaded (e.g. blocked by an ad blocker) — the
        // <ins> element just stays empty, which is the expected fallback.
      }
    });

    return ins;
  });
  return HtmlElementView(viewType: viewType);
}
