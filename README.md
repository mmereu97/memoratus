# 📖 Memoratus

**Learn any text by heart, the way you would with a sheet of paper and a ruler.** Built for learning prayers, poems or speeches, and used on my phone.

**Tech:** Flutter / Dart · custom text layout and painting · SharedPreferences · file_picker · share_plus · Google Fonts

---

## ✨ Features

### Three ways to read the same text
- **Original:** the full text.
- **Mask:** a **reveal ruler** you drag down the screen; only the lines above it are visible, so you recite the next line before you see it.
- **Condensed:** only the **first letter of each word**, the classic memorisation trick: enough to jog the memory, not enough to read.

Switching modes keeps your place in the text.

### Texts organised like a book
- Folders and texts in a tree (e.g. *Morning Prayers → Opening Prayers → Trisagion*), opened from a side drawer.
- **Formatting** with **B**old, *I*talic and **R**ed (for rubrics in liturgical texts): select a word, tap a button.
- Add a text by typing or pasting, or **import a `.txt` file**.

### Your texts are yours
- **Backup and restore:** export everything to a file and share it (e-mail, Drive, WhatsApp…); import it back, choosing to **merge** with or **replace** what is on the phone.
- Everything is stored on the device; nothing is sent anywhere.

### Under the hood
- The text is laid out with a **monospaced font** and wrapped by character count, so the ruler always lands exactly between two lines. The width of a character is **measured once per device** (a short calibration) and saved, so wrapping is identical on every screen size.
- The parsing of formatting tags and the line wrapping are covered by unit tests.

## 🚀 Build

```bash
flutter pub get
flutter test
flutter build apk --release
```

Android is the target I use; the project also contains the standard Flutter folders for iOS, web and desktop.

---

## 👤 Author

Mihai Mereu · [GitHub](https://github.com/mmereu97)
