import 'package:flutter/material.dart';
import 'package:tagkin_desktop/branding.g.dart';

/// Flutter asset for the signed-out poster (same file as the macOS Dock source).
const String kLoginHeroAsset = 'branding/icon_macos.png';

const String kLoginHeroTagline =
    'Who, what, when, and where in your photos and videos.';

/// Branded poster: TagFam art as a full-bleed graphic plus the app name.
class LoginHero extends StatelessWidget {
  const LoginHero({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      key: const Key('login-hero'),
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            kLoginHeroAsset,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.08),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x00000000), Color(0xA6000000)],
                stops: <double>[0.42, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                Text(
                  kAppName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  kLoginHeroTagline,
                  style: TextStyle(
                    color: Color(0xEBFFFFFF),
                    fontSize: 16,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
