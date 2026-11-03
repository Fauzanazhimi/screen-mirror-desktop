# Mirror Remote

Tampilkan layar laptop Windows di HP Android dan kendalikan dari HP, lewat
jaringan yang sama atau Tailscale.

- `host/`: program Dart untuk laptop (`mirror_host.exe`). Menangkap layar dan
  menerima input mouse/keyboard.
- `app/`: aplikasi Flutter untuk HP.
- `dist/`: hasil build siap pakai.

## Cara pakai

### Sekali di awal

1. Pasang Tailscale di laptop dan HP, lalu login dengan akun yang sama.
   Tailscale tidak diperlukan kalau hanya dipakai di Wi-Fi yang sama.
2. Pasang `dist/mirror_remote.apk` di HP. Android akan meminta izin memasang
   aplikasi dari luar Play Store.

### Setiap kali dipakai

1. Jalankan `dist/mirror_host.exe` di laptop dan biarkan jendelanya terbuka.
   Saat pertama dijalankan, Windows Firewall akan bertanya. Izinkan untuk
   jaringan **Private**.
2. Jendela host menampilkan kode pairing dan alamat laptop.
3. Di HP, buka Mirror Remote, isi alamat dan kode, lalu tekan Hubungkan.
   Alamat, port, dan kode tersimpan untuk pemakaian berikutnya.

Pakai alamat `100.x.y.z` untuk Tailscale, atau `192.168.x.x` kalau HP dan laptop
berada di Wi-Fi yang sama.

## Gestur

| Gestur | Mode touchpad | Mode sentuh |
| --- | --- | --- |
| Tap | Klik kiri di posisi kursor | Klik kiri di titik yang disentuh |
| Geser satu jari | Gerakkan kursor | Drag |
| Tahan lalu lepas | Klik kanan | Klik kanan |
| Tahan lalu geser | Drag | Drag |
| Tap dua jari | Klik kanan | Klik kanan |
| Geser dua jari | Scroll | Scroll (geser tampilan saat di-zoom) |
| Cubit | Zoom | Zoom |

Tombol `...` di kanan atas membuka menu: ganti mode, keyboard, tombol khusus
(Esc, Alt+Tab, Ctrl+C, panah, dan lainnya), reset zoom, kualitas, dan putuskan.

## Keamanan

- Siapa pun yang tahu kode pairing bisa melihat dan mengendalikan laptop.
  Jangan bagikan kodenya. Buat kode baru dengan `mirror_host --reset-code`.
- Kode tidak pernah dikirim lewat jaringan (login memakai HMAC-SHA256). Lima
  kali salah mengunci alamat tersebut selama 60 detik.
- Lewat Tailscale, seluruh lalu lintas terenkripsi oleh WireGuard.
- Lewat jaringan lokal, gambar layar dan ketikan **tidak terenkripsi**. Di Wi-Fi
  publik atau kampus, jalankan `mirror_host --tailscale-only` agar host hanya
  menerima koneksi Tailscale.

## Opsi host

```
mirror_host [--port 8765] [--tailscale-only] [--reset-code]
```

## Batasan

- Hanya monitor utama yang ditampilkan.
- Audio tidak ikut dikirim.
- Layar kunci dan prompt UAC tidak bisa ditangkap. Gambar akan berhenti sampai
  prompt tersebut selesai.
- Jendela yang berjalan sebagai Administrator tidak bisa dikendalikan, kecuali
  `mirror_host.exe` juga dijalankan sebagai Administrator.
- Ctrl+Alt+Del tidak bisa dikirim.
- Hanya satu HP yang tersambung dalam satu waktu; koneksi baru menggantikan yang
  lama.

## Kalau gagal terhubung

- Cek jendela host masih berjalan dan alamatnya benar.
- Pastikan Tailscale aktif di kedua perangkat.
- Jika jaringan Windows berstatus Public, izin firewall untuk jaringan Private
  tidak berlaku. Ubah jaringan ke Private, atau izinkan `mirror_host.exe` di
  Windows Security > Firewall > Allow an app through firewall.
- Gambar patah-patah: lihat statistik di jendela host. Kalau `latensi` terus di
  atas 500 ms, pilih kualitas **Hemat data** di menu. Koneksi Tailscale yang
  lewat relay (DERP) lebih lambat daripada koneksi langsung; jalankan
  `tailscale status` di laptop dan pastikan HP tertulis `direct`, bukan `relay`.

## Build ulang

```powershell
cd host
dart test
dart compile exe bin\mirror_host.dart -o build\mirror_host.exe

cd ..\app
flutter test
flutter build apk --release
```

Test terhadap host yang sedang berjalan (kursor laptop akan bergeser sedikit):

```powershell
$env:MIRROR_E2E_PORT='8765'
$env:MIRROR_E2E_CODE='KODE-PAIRING'
flutter test test/host_e2e_test.dart
```

Mengukur kinerja tanpa HP. `net_sim` meniru jaringan lambat, misalnya 1 Mbps
dengan delay 80 ms:

```powershell
cd host
dart run tool/bench_capture.dart 1280 60
dart run tool/net_sim.dart 18766 8765 1000 80
dart run tool/smoke_client.dart 127.0.0.1 18766 KODE-PAIRING 12 move
```

`kotlin.incremental=false` di `app/android/gradle.properties` diperlukan karena
proyek berada di drive D: sedangkan Pub cache di C:.
