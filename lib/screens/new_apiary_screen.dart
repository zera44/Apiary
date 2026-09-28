import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'map_screen.dart';

/// Створення нової пасіки: назва + місце на карті (OpenStreetMap, без
/// платного API-ключа). Місце обирається тапом по карті; за наявності
/// дозволу застосунок сам показує поточну геолокацію.
class NewApiaryScreen extends StatefulWidget {
  final Repository repo;
  const NewApiaryScreen({super.key, required this.repo});
  @override
  State<NewApiaryScreen> createState() => _NewApiaryScreenState();
}

class _NewApiaryScreenState extends State<NewApiaryScreen> {
  // центр України — запасний варіант, якщо геолокація недоступна
  static const _fallback = LatLng(48.3794, 31.1656);

  final _nameCtrl = TextEditingController();
  final _mapController = MapController();
  LatLng _center = _fallback;
  LatLng? _picked;
  bool _locating = true;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _locate(initial: true);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  /// Спроба визначити поточну геолокацію; будь-яка відмова (немає
  /// дозволу, вимкнена служба, тайм-аут) просто лишає запасний центр —
  /// це необов'язкова зручність, а не обов'язкова умова.
  Future<void> _locate({bool initial = false}) async {
    if (!initial) setState(() => _locating = true);
    LatLng? found;
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.denied && perm != LocationPermission.deniedForever) {
        if (await Geolocator.isLocationServiceEnabled()) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 6),
            ),
          );
          found = LatLng(pos.latitude, pos.longitude);
        }
      }
    } catch (_) {
      // без геолокації — користувач обере місце тапом по карті
    }
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (found != null) {
        _center = found!;
        _picked = found;
      }
    });
    if (found != null) {
      _mapController.move(found, 15);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введіть назву пасіки');
      return;
    }
    if (_saving) return;
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final id = await widget.repo.addApiary(name, lat: _picked?.latitude, lon: _picked?.longitude);
      final apiary = await widget.repo.getApiary(id);
      if (!mounted || apiary == null) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => MapScreen(repo: widget.repo, apiary: apiary),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Column(children: [
          TopBar(title: 'Нова пасіка', onBack: () => Navigator.pop(context)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: TextStyle(color: AppColors.text),
              decoration: const InputDecoration(hintText: 'Назва пасіки'),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Торкніться карти, щоб позначити місце пасіки',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: _picked != null ? 15 : 6,
                      onTap: (_, point) => setState(() => _picked = point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'org.apiary.apiary',
                      ),
                      if (_picked != null)
                        MarkerLayer(markers: [
                          Marker(
                            point: _picked!,
                            width: 42,
                            height: 42,
                            alignment: Alignment.topCenter,
                            child: Icon(Icons.location_pin, color: AppColors.danger, size: 42),
                          ),
                        ]),
                    ],
                  ),
                  if (_locating)
                    const Positioned(
                      top: 10,
                      right: 10,
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: FloatingActionButton.small(
                      heroTag: null,
                      backgroundColor: AppColors.roundBtn,
                      foregroundColor: AppColors.text,
                      tooltip: 'Моя геолокація',
                      onPressed: () => _locate(),
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
                ),
              PillButton(
                text: _saving ? 'Створюємо…' : 'OK',
                bg: AppColors.accent,
                height: 50,
                radius: 16,
                width: double.infinity,
                onPressed: _saving ? null : _save,
              ),
            ]),
          ),
          ]),
          const Positioned.fill(child: ScreenFrame()),
        ]),
      ),
    );
  }
}
