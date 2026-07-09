# Suara Notifikasi

Letakkan berkas suara notifikasi di folder ini. Nama berkas dirujuk dari
Pengaturan aplikasi (`SettingsRepository.soundName`) dan dimainkan oleh
`NotificationService` melalui `audioplayers`.

Berkas yang didukung UI secara default:

- `alert.mp3`
- `chime.mp3`
- `ping.mp3`

Jika berkas tidak ada, aplikasi tetap berjalan normal — pemutaran suara
dibungkus `try/catch` sehingga kegagalan aset diabaikan dengan aman. Ganti
berkas ini dengan aset `.mp3` Anda sendiri sebelum rilis produksi.
