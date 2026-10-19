import 'package:app/domain/entities/update_info.dart';
import 'package:app/ui/core/themes/themes.dart';
import 'package:app/ui/update/states/update_banner_state.dart';
import 'package:app/ui/update/viewmodels/update_banner_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:app/ui/core/widgets/widgets.dart';
import 'package:provider/provider.dart';

/// Aviso de atualização in-app (plano 44, passo 3). Renderiza nada quando não
/// há versão nova a anunciar (iOS, sem update, dispensada, manifest
/// indisponível) — o gate Android-only vive no [UpdateBannerViewModel.enabled].
///
/// Dispara o check silencioso no primeiro mount (= startup da Home). Tocar
/// oferece o download do APK e dispensa a versão quando solicitado.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  @override
  void initState() {
    super.initState();
    // `context.read` é seguro no initState (não assina). Best-effort: o check
    // se auto-silencia em qualquer falha e é no-op fora do Android.
    context.read<UpdateBannerViewModel>().check();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<UpdateBannerViewModel>().state;
    return switch (state) {
      UpdateBannerHidden() => const SizedBox.shrink(),
      UpdateBannerVisible(:final info) => _UpdateCard(info: info),
    };
  }
}

/// Neutral update notice above the dashboard filters.
class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<UpdateBannerViewModel>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: AppBanner(
              key: const Key('update-banner-download'),
              message: 'Update available · v${info.version}',
              actionLabel: 'Download',
              onAction: vm.download,
            ),
          ),
          TextButton(
            key: const Key('update-banner-dismiss'),
            onPressed: vm.dismiss,
            child: Text(
              'Dismiss',
              style: context.typo.footnote.copyWith(
                color: context.colors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
