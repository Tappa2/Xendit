import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

const primaryOrange = Color(0xFFEE4D2D);
const darkBg = Color(0xFFF7F7F7);
const cardBg = Colors.white;
const textDark = Color(0xFF222222);
const textGray = Color(0xFF888888);
const borderLight = Color(0xFFEFEFEF);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const StreetwearApp());
}

class StreetwearApp extends StatelessWidget {
  const StreetwearApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Streetwear Men, Women & Babies',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: darkBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryOrange,
          primary: primaryOrange,
          surface: cardBg,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: cardBg,
          foregroundColor: textDark,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: textDark, fontSize: 18, fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF0F0F0),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: primaryOrange, width: 1.2)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryOrange,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            elevation: 0,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          backgroundColor: textDark,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }
        if (snapshot.data != null) return const StoreShell();
        return const LoginScreen();
      },
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(color: primaryOrange)),
  );
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String money(num value) => '₱${value.toStringAsFixed(2)}';

num parsePrice(dynamic value) {
  if (value is num) return value;
  return num.tryParse((value ?? '0').toString().replaceAll(',', '').replaceAll('₱', '').trim()) ?? 0;
}

class Product {
  final String id;
  final String name;
  final String category;
  final String description;
  final String imageUrl;
  final num price;
  final List<String> sizes;
  final List<String> colors;
  final int stock;
  final bool featured;

  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.imageUrl,
    required this.price,
    required this.sizes,
    required this.colors,
    required this.stock,
    required this.featured,
  });

  factory Product.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    List<String> stringList(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : <String>[];
    return Product(
      id: doc.id,
      name: (d['name'] ?? 'Streetwear Item').toString(),
      category: (d['category'] ?? 'All').toString(),
      description: (d['description'] ?? 'A premium urban streetwear piece designed for ultimate style.').toString(),
      imageUrl: (d['imageUrl'] ?? d['imageURL'] ?? '').toString(),
      price: parsePrice(d['price']),
      sizes: stringList(d['sizes']).isEmpty ? ['S', 'M', 'L', 'XL'] : stringList(d['sizes']),
      colors: stringList(d['colors']),
      stock: (d['stock'] is num) ? (d['stock'] as num).toInt() : 99,
      featured: d['isFeatured'] == true,
    );
  }
}

class CartLine {
  final Product product;
  int quantity;
  String size;
  String color;
  CartLine({required this.product, this.quantity = 1, required this.size, required this.color});
  num get subtotal => product.price * quantity;
}

class StoreShell extends StatefulWidget {
  const StoreShell({super.key});
  @override
  State<StoreShell> createState() => _StoreShellState();
}

class _StoreShellState extends State<StoreShell> {
  int tab = 0;
  final Map<String, CartLine> cart = {};
  final Set<String> localWishlist = {};
  final searchController = TextEditingController();
  String search = '';
  String category = 'All';
  bool placingOrder = false;
  bool voucherClaimed = false;

  @override
  void initState() {
    super.initState();
    _seedProductsIfNeeded();
  }

  Future<void> _seedProductsIfNeeded() async {
    try {
      final col = FirebaseFirestore.instance.collection('products');
      final snapshot = await col.get();
      if (snapshot.docs.isEmpty) {
        final initialProducts = [
          // MEN (10 items)
          {
            'name': 'Oversized Urban Graphic Hoodie (Men)',
            'category': 'Men',
            'description': 'Heavyweight fleece cotton hoodie with striking back graphic print.',
            'imageUrl': 'https://images.unsplash.com/photo-1556905055-8f358a7a47b2?auto=format&fit=crop&w=600&q=80',
            'price': 1499,
            'sizes': ['S', 'M', 'L', 'XL'],
            'colors': ['Black', 'Charcoal', 'Grey'],
            'stock': 30,
            'isFeatured': true,
          },
          {
            'name': 'Minimalist Heavyweight Boxy Tee (Men)',
            'category': 'Men',
            'description': '240GSM thick cotton boxy fit t-shirt for clean everyday aesthetics.',
            'imageUrl': 'https://images.unsplash.com/photo-1521572267360-ee0c2909d518?auto=format&fit=crop&w=600&q=80',
            'price': 699,
            'sizes': ['S', 'M', 'L', 'XL'],
            'colors': ['White', 'Black', 'Off-White'],
            'stock': 50,
            'isFeatured': false,
          },
          {
            'name': 'Utility Cargo Street Pants (Men)',
            'category': 'Men',
            'description': 'Multi-pocket tactical utility cargo pants built for comfort and style.',
            'imageUrl': 'https://images.unsplash.com/photo-1517445312882-bc9910d016b7?auto=format&fit=crop&w=600&q=80',
            'price': 1399,
            'sizes': ['S', 'M', 'L', 'XL'],
            'colors': ['Black', 'Khaki', 'Olive'],
            'stock': 25,
            'isFeatured': true,
          },
          {
            'name': 'Distressed Denim Biker Jacket (Men)',
            'category': 'Men',
            'description': 'Edgy rugged denim jacket with washed detailing and structured shoulders.',
            'imageUrl': 'https://images.unsplash.com/photo-1576995853123-5a10305d93c0?auto=format&fit=crop&w=600&q=80',
            'price': 2299,
            'sizes': ['M', 'L', 'XL'],
            'colors': ['Blue', 'Black'],
            'stock': 15,
            'isFeatured': false,
          },
          {
            'name': 'Techwear Windbreaker Jacket (Men)',
            'category': 'Men',
            'description': 'Water-resistant lightweight windbreaker featuring cyberpunk hardware.',
            'imageUrl': 'https://images.unsplash.com/photo-1548883354-7622d03aca27?auto=format&fit=crop&w=600&q=80',
            'price': 1899,
            'sizes': ['S', 'M', 'L', 'XL'],
            'colors': ['Black', 'Navy'],
            'stock': 20,
            'isFeatured': true,
          },
          {
            'name': 'Graphic Streetwear Sweatshorts (Men)',
            'category': 'Men',
            'description': 'Breathable French terry fleece shorts for laidback summer fits.',
            'imageUrl': 'https://images.unsplash.com/photo-1591195853828-11db59a44f6b?auto=format&fit=crop&w=600&q=80',
            'price': 799,
            'sizes': ['S', 'M', 'L', 'XL'],
            'colors': ['Grey', 'Black'],
            'stock': 35,
            'isFeatured': false,
          },
          {
            'name': 'Flannel Overshirt Plaid Jacket (Men)',
            'category': 'Men',
            'description': 'Soft brushed cotton flannel shirt jacket for effortless layering.',
            'imageUrl': 'https://images.unsplash.com/photo-1608256246200-53e635b5b65f?auto=format&fit=crop&w=600&q=80',
            'price': 1199,
            'sizes': ['M', 'L', 'XL'],
            'colors': ['Red/Black', 'Green/Black'],
            'stock': 18,
            'isFeatured': false,
          },
          {
            'name': 'Ribbed Crewneck Pullover (Men)',
            'category': 'Men',
            'description': 'Minimalist cozy pullover sweater designed with dropped shoulders.',
            'imageUrl': 'https://images.unsplash.com/photo-1620799140408-edc6dcb6d633?auto=format&fit=crop&w=600&q=80',
            'price': 1099,
            'sizes': ['S', 'M', 'L', 'XL'],
            'colors': [' Oatmeal', 'Black'],
            'stock': 22,
            'isFeatured': false,
          },
          {
            'name': 'Pleated Wide-Leg Trouser (Men)',
            'category': 'Men',
            'description': 'Draped high-waist wide-leg trousers for smart-casual streetwear.',
            'imageUrl': 'https://images.unsplash.com/photo-1594938298603-c8148c4dae35?auto=format&fit=crop&w=600&q=80',
            'price': 1499,
            'sizes': ['S', 'M', 'L'],
            'colors': ['Black', 'Charcoal'],
            'stock': 15,
            'isFeatured': false,
          },
          {
            'name': 'Puffer Vest Sleeveless Jacket (Men)',
            'category': 'Men',
            'description': 'Insulated quilted puffer vest with high collar protection.',
            'imageUrl': 'https://images.unsplash.com/photo-1544441893-675973e31985?auto=format&fit=crop&w=600&q=80',
            'price': 1699,
            'sizes': ['M', 'L', 'XL'],
            'colors': ['Matte Black', 'Olive'],
            'stock': 12,
            'isFeatured': true,
          },

          // WOMEN (10 items)
          {
            'name': 'Y2K Cargo Parachute Pants (Women)',
            'category': 'Women',
            'description': 'Relaxed-fit low-waist parachute cargo pants with adjustable drawstrings.',
            'imageUrl': 'https://images.unsplash.com/photo-1517445312882-bc9910d016b7?auto=format&fit=crop&w=600&q=80',
            'price': 1299,
            'sizes': ['XS', 'S', 'M', 'L'],
            'colors': ['Beige', 'Black', 'Army Green'],
            'stock': 25,
            'isFeatured': true,
          },
          {
            'name': 'Crop Ribbed Tank & Jogger Set (Women)',
            'category': 'Women',
            'description': 'Comfortable ribbed cotton crop top paired with high-waist joggers.',
            'imageUrl': 'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?auto=format&fit=crop&w=600&q=80',
            'price': 1599,
            'sizes': ['XS', 'S', 'M'],
            'colors': ['Pink', 'Black', 'Heather Grey'],
            'stock': 20,
            'isFeatured': true,
          },
          {
            'name': 'Oversized Aesthetic Zip Hoodie (Women)',
            'category': 'Women',
            'description': 'Cozy zip-up hoodie featuring an oversized boyfriend fit.',
            'imageUrl': 'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?auto=format&fit=crop&w=600&q=80',
            'price': 1399,
            'sizes': ['S', 'M', 'L'],
            'colors': ['Lilac', 'Black', 'Cream'],
            'stock': 30,
            'isFeatured': false,
          },
          {
            'name': 'High-Waist Wide Leg Denim Jeans (Women)',
            'category': 'Women',
            'description': 'Vintage wash high-rise denim jeans with a flattering wide-leg cut.',
            'imageUrl': 'https://images.unsplash.com/photo-1541099649105-f69ad21f3246?auto=format&fit=crop&w=600&q=80',
            'price': 1499,
            'sizes': ['XS', 'S', 'M', 'L'],
            'colors': ['Light Blue', 'Vintage Wash'],
            'stock': 25,
            'isFeatured': true,
          },
          {
            'name': 'Mesh Long Sleeve Graphic Top (Women)',
            'category': 'Women',
            'description': 'Sheer mesh top with vibrant artistic print for layering.',
            'imageUrl': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=600&q=80',
            'price': 599,
            'sizes': ['XS', 'S', 'M'],
            'colors': ['Multi', 'Black Abstract'],
            'stock': 40,
            'isFeatured': false,
          },
          {
            'name': 'Pleated Tennis Mini Skirt (Women)',
            'category': 'Women',
            'description': 'Classic high-waist pleated skater skirt with built-in shorts.',
            'imageUrl': 'https://images.unsplash.com/photo-1583496661160-fb5886a0aaaa?auto=format&fit=crop&w=600&q=80',
            'price': 699,
            'sizes': ['XS', 'S', 'M', 'L'],
            'colors': ['Black', 'White', 'Plaid'],
            'stock': 35,
            'isFeatured': false,
          },
          {
            'name': 'Faux Leather Cropped Biker Jacket (Women)',
            'category': 'Women',
            'description': 'Edgy cropped vegan leather jacket with silver zipper accents.',
            'imageUrl': 'https://images.unsplash.com/photo-1551028719-00167b16eac5?auto=format&fit=crop&w=600&q=80',
            'price': 1999,
            'sizes': ['S', 'M', 'L'],
            'colors': ['Black', 'Dark Brown'],
            'stock': 15,
            'isFeatured': true,
          },
          {
            'name': 'Sleek Bodycon Mini Dress (Women)',
            'category': 'Women',
            'description': 'Ribbed cotton stretch dress designed for effortless street style.',
            'imageUrl': 'https://images.unsplash.com/photo-1539109136881-3be0616acf4b?auto=format&fit=crop&w=600&q=80',
            'price': 899,
            'sizes': ['XS', 'S', 'M'],
            'colors': ['Black', 'Olive', 'Beige'],
            'stock': 28,
            'isFeatured': false,
          },
          {
            'name': 'Puffer Cropped Vest (Women)',
            'category': 'Women',
            'description': 'Trendy cropped winter puffer vest with high warmth-to-weight ratio.',
            'imageUrl': 'https://images.unsplash.com/photo-1516257984-b1b4d707412e?auto=format&fit=crop&w=600&q=80',
            'price': 1399,
            'sizes': ['S', 'M', 'L'],
            'colors': ['White', 'Black', 'Pink'],
            'stock': 18,
            'isFeatured': false,
          },
          {
            'name': 'Oversized Boyfriend Blazer (Women)',
            'category': 'Women',
            'description': 'Structured tailored blazer for an elevated smart streetwear vibe.',
            'imageUrl': 'https://images.unsplash.com/photo-1490481651871-ab68de25d43d?auto=format&fit=crop&w=600&q=80',
            'price': 1799,
            'sizes': ['S', 'M', 'L'],
            'colors': ['Black', 'Beige Plaid'],
            'stock': 14,
            'isFeatured': false,
          },

          // BABIES (10 items)
          {
            'name': 'Mini Streetwear Cotton Hoodie (Baby)',
            'category': 'Babies',
            'description': 'Adorable miniature pullover fleece hoodie for stylish toddlers.',
            'imageUrl': 'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?auto=format&fit=crop&w=600&q=80',
            'price': 599,
            'sizes': ['0-6M', '6-12M', '12-18M', '18-24M'],
            'colors': ['Grey', 'Black', 'Pink'],
            'stock': 40,
            'isFeatured': true,
          },
          {
            'name': 'Tiny Cargo Jogger Pants (Baby)',
            'category': 'Babies',
            'description': 'Super comfortable elastic-waist baby cargo pants with mini side pockets.',
            'imageUrl': 'https://images.unsplash.com/photo-1519689680058-324335c77eba?auto=format&fit=crop&w=600&q=80',
            'price': 499,
            'sizes': ['0-6M', '6-12M', '12-18M'],
            'colors': ['Khaki', 'Black', 'Olive'],
            'stock': 35,
            'isFeatured': false,
          },
          {
            'name': 'Baby Street Style Denim Jacket (Baby)',
            'category': 'Babies',
            'description': 'Soft stretchy denim jacket scaled down for infants and toddlers.',
            'imageUrl': 'https://images.unsplash.com/photo-1502767089025-6572583495f9?auto=format&fit=crop&w=600&q=80',
            'price': 799,
            'sizes': ['6-12M', '12-18M', '18-24M'],
            'colors': ['Light Wash', 'Dark Wash'],
            'stock': 20,
            'isFeatured': true,
          },
          {
            'name': 'Infant Graphic Romper Bodysuit (Baby)',
            'category': 'Babies',
            'description': 'Breathable cotton snap romper with cool urban typography.',
            'imageUrl': 'https://images.unsplash.com/photo-1519689680058-324335c77eba?auto=format&fit=crop&w=600&q=80',
            'price': 399,
            'sizes': ['0-3M', '3-6M', '6-12M'],
            'colors': ['White', 'Black', 'Grey'],
            'stock': 50,
            'isFeatured': false,
          },
          {
            'name': 'Toddler Tracksuit Set (Baby)',
            'category': 'Babies',
            'description': 'Matching zip jacket and sweatpant athletic set for little trendsetters.',
            'imageUrl': 'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?auto=format&fit=crop&w=600&q=80',
            'price': 899,
            'sizes': ['6-12M', '12-18M', '18-24M', '2T'],
            'colors': ['Black', 'Navy', 'Beige'],
            'stock': 25,
            'isFeatured': false,
          },
          {
            'name': 'Mini Puffer Vest Jacket (Baby)',
            'category': 'Babies',
            'description': 'Quilted sleeveless puffer vest to keep toddlers warm and stylish.',
            'imageUrl': 'https://images.unsplash.com/photo-1502767089025-6572583495f9?auto=format&fit=crop&w=600&q=80',
            'price': 699,
            'sizes': ['12-18M', '18-24M', '2T', '3T'],
            'colors': ['Black', 'Yellow', 'Olive'],
            'stock': 22,
            'isFeatured': false,
          },
          {
            'name': 'Baby Ribbed Knit Beanie & Scarf Set',
            'category': 'Babies',
            'description': 'Cozy soft knit winter cap and mini scarf set.',
            'imageUrl': 'https://images.unsplash.com/photo-1519689680058-324335c77eba?auto=format&fit=crop&w=600&q=80',
            'price': 349,
            'sizes': ['One Size'],
            'colors': ['Grey', 'Cream', 'Black'],
            'stock': 45,
            'isFeatured': false,
          },
          {
            'name': 'Tiny Oversized Pocket Tee (Baby)',
            'category': 'Babies',
            'description': 'Cute boxy fit t-shirt with a tiny functional chest pocket.',
            'imageUrl': 'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?auto=format&fit=crop&w=600&q=80',
            'price': 299,
            'sizes': ['3-6M', '6-12M', '12-18M', '18-24M'],
            'colors': ['White', 'Off-White', 'Black'],
            'stock': 60,
            'isFeatured': false,
          },
          {
            'name': 'Baby Fleece Overalls Dungarees (Baby)',
            'category': 'Babies',
            'description': 'Comfortable cotton fleece overalls with adjustable button straps.',
            'imageUrl': 'https://images.unsplash.com/photo-1502767089025-6572583495f9?auto=format&fit=crop&w=600&q=80',
            'price': 699,
            'sizes': ['0-6M', '6-12M', '12-18M'],
            'colors': ['Brown', 'Grey', 'Black'],
            'stock': 28,
            'isFeatured': true,
          },
          {
            'name': 'Mini Flannel Check Shirt (Baby)',
            'category': 'Babies',
            'description': 'Classic plaid button-down cotton shirt for mini streetwear looks.',
            'imageUrl': 'https://images.unsplash.com/photo-1519689680058-324335c77eba?auto=format&fit=crop&w=600&q=80',
            'price': 499,
            'sizes': ['6-12M', '12-18M', '18-24M', '2T'],
            'colors': ['Red Plaid', 'Blue Plaid'],
            'stock': 30,
            'isFeatured': false,
          },
        ];

        for (final p in initialProducts) {
          await col.add(p);
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  int get cartCount => cart.values.fold(0, (sum, line) => sum + line.quantity);
  num get rawCartTotal => cart.values.fold<num>(0, (sum, line) => sum + line.subtotal);
  num get cartTotal => voucherClaimed ? rawCartTotal * 0.8 : rawCartTotal;

  void addToCart(Product product, String size, String color) {
    final key = '${product.id}_${size}_${color}';
    setState(() {
      if (cart.containsKey(key)) {
        cart[key]!.quantity++;
      } else {
        cart[key] = CartLine(product: product, size: size, color: color);
      }
    });
    showMessage(context, 'Added to your Shopping Bag!');
  }

  void changeQuantity(String key, int delta) {
    setState(() {
      final line = cart[key];
      if (line == null) return;
      line.quantity += delta;
      if (line.quantity <= 0) cart.remove(key);
    });
  }

  Future<void> toggleWishlist(Product product) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance
        .collection('users').doc(uid).collection('wishlist').doc(product.id);
    final isSaved = localWishlist.contains(product.id);
    setState(() {
      if (isSaved) {
        localWishlist.remove(product.id);
      } else {
        localWishlist.add(product.id);
      }
    });
    try {
      if (isSaved) {
        await ref.delete();
      } else {
        await ref.set({
          'productId': product.id,
          'name': product.name,
          'price': product.price,
          'imageUrl': product.imageUrl,
          'category': product.category,
          'savedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
  }

  Future<void> checkout() async {
    if (cart.isEmpty || placingOrder) return;
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: FirebaseAuth.instance.currentUser?.displayName ?? '');
    final phone = TextEditingController();
    final address = TextEditingController();
    String paymentMethod = 'Cash on Delivery';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  const Text('Checkout & Payment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  const Text('Select your preferred payment method', style: TextStyle(color: textGray, fontSize: 12)),
                  const SizedBox(height: 16),
                  TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Full Name'), validator: (v) => v!.isEmpty ? 'Please enter your name' : null),
                  const SizedBox(height: 10),
                  TextFormField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile Number'), validator: (v) => v!.isEmpty ? 'Please enter your phone number' : null),
                  const SizedBox(height: 10),
                  TextFormField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'Complete Shipping Address'), validator: (v) => v!.isEmpty ? 'Please enter your address' : null),
                  const SizedBox(height: 16),
                  const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('COD', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          value: 'Cash on Delivery',
                          groupValue: paymentMethod,
                          activeColor: primaryOrange,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) => setSheetState(() => paymentMethod = val!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('GCash', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          value: 'GCash',
                          groupValue: paymentMethod,
                          activeColor: primaryOrange,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) => setSheetState(() => paymentMethod = val!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: [
                        if (voucherClaimed) ...[
                          Row(children: [const Expanded(child: Text('Subtotal')), Text(money(rawCartTotal), style: const TextStyle(color: textGray))]),
                          const SizedBox(height: 4),
                          Row(children: [const Expanded(child: Text('New User 20% Voucher', style: TextStyle(color: primaryOrange, fontWeight: FontWeight.bold))), Text('-${money(rawCartTotal * 0.2)}', style: const TextStyle(color: primaryOrange, fontWeight: FontWeight.bold))]),
                          const Divider(height: 12),
                        ],
                        Row(children: [const Expanded(child: Text('Total Amount Due', style: TextStyle(fontWeight: FontWeight.bold))), Text(money(cartTotal), style: const TextStyle(fontWeight: FontWeight.w900, color: primaryOrange, fontSize: 16))]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      if (formKey.currentState!.validate()) Navigator.pop(sheetContext, true);
                    },
                    child: Text(paymentMethod == 'GCash' ? 'PAY VIA GCASH' : 'PLACE ORDER (COD)'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    if (paymentMethod == 'GCash') {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('GCash Payment Portal'),
          content: Text('Please send the total amount of ${money(cartTotal)} to GCash Number:\n\n📱 0917-123-4567 (Streetwear Store)\n\nTap "Confirm Payment" after transferring.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Confirm Payment')),
          ],
        ),
      );
    }

    setState(() => placingOrder = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final items = cart.values.map((line) => {
        'productId': line.product.id,
        'name': line.product.name,
        'imageUrl': line.product.imageUrl,
        'unitPrice': line.product.price,
        'quantity': line.quantity,
        'size': line.size,
        'color': line.color,
        'subtotal': line.subtotal,
      }).toList();

      await FirebaseFirestore.instance.collection('orders').add({
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'customerName': name.text.trim(),
        'phone': phone.text.trim(),
        'shippingAddress': address.text.trim(),
        'items': items,
        'total': cartTotal,
        'voucherApplied': voucherClaimed,
        'status': 'Pending',
        'paymentMethod': paymentMethod,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() {
        cart.clear();
        tab = 3;
      });
      showMessage(context, 'Order placed successfully ($paymentMethod)!');
    } catch (_) {
      showMessage(context, 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => placingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildShop(),
      _buildWishlist(),
      _buildCart(),
      _buildOrders(),
      _buildProfile(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: primaryOrange, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.bolt, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
            const Text('STREETWEAR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _openCommunityChat(context),
            icon: const Icon(Icons.headset_mic_outlined),
            tooltip: 'Customer Support',
          ),
          IconButton(
            onPressed: () => setState(() => tab = 2),
            icon: Badge(
              label: Text('$cartCount'),
              isLabelVisible: cartCount > 0,
              backgroundColor: primaryOrange,
              child: const Icon(Icons.shopping_bag_outlined),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        backgroundColor: cardBg,
        indicatorColor: primaryOrange.withOpacity(0.15),
        elevation: 10,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront, color: primaryOrange), label: 'Shop'),
          const NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite, color: primaryOrange), label: 'Wishlist'),
          NavigationDestination(
            icon: Badge(label: Text('$cartCount'), isLabelVisible: cartCount > 0, backgroundColor: primaryOrange, child: const Icon(Icons.shopping_bag_outlined)),
            selectedIcon: Badge(label: Text('$cartCount'), isLabelVisible: cartCount > 0, backgroundColor: primaryOrange, child: const Icon(Icons.shopping_bag, color: primaryOrange)),
            label: 'Bag',
          ),
          const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long, color: primaryOrange), label: 'Orders'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: primaryOrange), label: 'Profile'),
        ],
      ),
    );
  }

  void _openCommunityChat(BuildContext context) {
    final messageController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SizedBox(
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.support_agent, color: primaryOrange, size: 28),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Customer Support & Admin', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      Text('We are online to assist with any issues!', style: TextStyle(fontSize: 11, color: textGray)),
                    ],
                  ),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const Divider(height: 20),
              Expanded(
                child: ListView(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
                        child: const Text('Hello! Welcome to Streetwear Admin Support. How can we help you today with your order or clothing size?', style: TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      decoration: const InputDecoration(hintText: 'Type your message to admin...'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    style: IconButton.styleFrom(backgroundColor: primaryOrange, foregroundColor: Colors.white),
                    onPressed: () {
                      if (messageController.text.trim().isNotEmpty) {
                        showMessage(context, 'Message sent to Admin successfully!');
                        messageController.clear();
                      }
                    },
                    icon: const Icon(Icons.send, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShop() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('products').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Error loading store.'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: primaryOrange));

        final products = (snapshot.data?.docs ?? []).map(Product.fromDoc).toList();
        final categories = <String>['All', ...{for (final p in products) if (p.category.isNotEmpty) p.category}];
        final filtered = products.where((p) {
          final matchesSearch = p.name.toLowerCase().contains(search.toLowerCase()) || p.category.toLowerCase().contains(search.toLowerCase());
          final matchesCategory = category == 'All' || p.category == category;
          return matchesSearch && matchesCategory;
        }).toList();

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Shopee / TikTok Style New User Voucher Banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFEE4D2D), Color(0xFFFF7337)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.local_activity, color: Colors.white, size: 40),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('NEW USER EXCLUSIVE', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                                const Text('Claim 20% OFF Voucher', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 2),
                                Text(voucherClaimed ? 'Voucher Successfully Claimed!' : 'Tap to claim and save on your first order.', style: const TextStyle(color: Colors.white, fontSize: 11)),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: primaryOrange,
                              minimumSize: const Size(80, 36),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            onPressed: voucherClaimed ? null : () {
                              setState(() => voucherClaimed = true);
                              showMessage(context, '20% New User Voucher Claimed!');
                            },
                            child: Text(voucherClaimed ? 'CLAIMED' : 'CLAIM', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF171614), Color(0xFF33302C)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: primaryOrange, borderRadius: BorderRadius.circular(4)),
                                  child: const Text('MEN, WOMEN & BABIES', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(height: 6),
                                const Text('Urban Streetwear', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 2),
                                const Text('Level up your daily drip with our latest collection.', style: TextStyle(color: Colors.white70, fontSize: 11)),
                              ],
                            ),
                          ),
                          const Icon(Icons.local_fire_department_rounded, color: primaryOrange, size: 48),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: searchController,
                      onChanged: (v) => setState(() => search = v),
                      decoration: InputDecoration(
                        hintText: 'Search hoodies, pants, tees, baby wear...',
                        prefixIcon: const Icon(Icons.search, size: 20, color: textGray),
                        suffixIcon: search.isNotEmpty ? IconButton(onPressed: () { searchController.clear(); setState(() => search = ''); }, icon: const Icon(Icons.close, size: 18)) : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: categories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final c = categories[index];
                          final selected = c == category;
                          return ChoiceChip(
                            label: Text(c, style: TextStyle(fontSize: 12, color: selected ? Colors.white : textDark, fontWeight: FontWeight.w700)),
                            selected: selected,
                            onSelected: (_) => setState(() => category = c),
                            backgroundColor: cardBg,
                            selectedColor: primaryOrange,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            side: BorderSide(color: selected ? primaryOrange : borderLight),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Featured Collections', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ),
            filtered.isEmpty
                ? const SliverFillRemaining(child: Center(child: Text('No products found.', style: TextStyle(color: textGray))))
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, childAspectRatio: 0.62, crossAxisSpacing: 10, mainAxisSpacing: 10,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => ProductCard(
                          product: filtered[index],
                          wished: localWishlist.contains(filtered[index].id),
                          onWishlist: () => toggleWishlist(filtered[index]),
                          onTap: () => showProductDetails(filtered[index]),
                        ),
                        childCount: filtered.length,
                      ),
                    ),
                  ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }

  void showProductDetails(Product product) {
    String size = product.sizes.first;
    String color = product.colors.isNotEmpty ? product.colors.first : 'Default';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cardBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 1.2,
                    child: product.imageUrl.isEmpty ? const ProductPlaceholder() : Image.network(product.imageUrl, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 14),
                Text(product.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(money(product.price), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: primaryOrange)),
                const SizedBox(height: 10),
                Text(product.description, style: const TextStyle(color: textGray, fontSize: 13, height: 1.4)),
                const SizedBox(height: 14),
                const Text('Size', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, children: product.sizes.map((s) => ChoiceChip(
                  label: Text(s), selected: size == s, onSelected: (_) => setSheetState(() => size = s),
                  selectedColor: primaryOrange, backgroundColor: const Color(0xFFF5F5F5),
                  labelStyle: TextStyle(color: size == s ? Colors.white : textDark, fontWeight: FontWeight.bold),
                )).toList()),
                if (product.colors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, children: product.colors.map((c) => ChoiceChip(
                    label: Text(c), selected: color == c, onSelected: (_) => setSheetState(() => color = c),
                    selectedColor: primaryOrange, backgroundColor: const Color(0xFFF5F5F5),
                    labelStyle: TextStyle(color: color == c ? Colors.white : textDark, fontWeight: FontWeight.bold),
                  )).toList()),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: product.stock <= 0 ? null : () {
                    Navigator.pop(sheetContext);
                    addToCart(product, size, color);
                  },
                  child: Text(product.stock <= 0 ? 'OUT OF STOCK' : 'ADD TO BAG'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWishlist() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('wishlist').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: primaryOrange));
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No items saved in Wishlist yet.', style: TextStyle(color: textGray)));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('My Wishlist', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            ...docs.map((doc) {
              final d = doc.data();
              final product = Product(
                id: doc.id, name: (d['name'] ?? '').toString(), category: '', description: '',
                imageUrl: (d['imageUrl'] ?? '').toString(), price: parsePrice(d['price']),
                sizes: const ['S', 'M', 'L'], colors: const [], stock: 99, featured: false,
              );
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 65, height: 75, child: Image.network(product.imageUrl, fit: BoxFit.cover))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(money(product.price), style: const TextStyle(color: primaryOrange, fontWeight: FontWeight.w900)),
                  ])),
                  IconButton(onPressed: () => toggleWishlist(product), icon: const Icon(Icons.favorite, color: primaryOrange)),
                ]),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildCart() {
    if (cart.isEmpty) return const Center(child: Text('Your Shopping Bag is empty.', style: TextStyle(color: textGray)));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Shopping Bag', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        ...cart.entries.map((entry) {
          final line = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 65, height: 75, child: Image.network(line.product.imageUrl, fit: BoxFit.cover))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text('${line.size} | ${line.color}', style: const TextStyle(color: textGray, fontSize: 11)),
                const SizedBox(height: 4),
                Text(money(line.subtotal), style: const TextStyle(fontWeight: FontWeight.w900, color: primaryOrange)),
                Row(children: [
                  IconButton(visualDensity: VisualDensity.compact, onPressed: () => changeQuantity(entry.key, -1), icon: const Icon(Icons.remove_circle_outline, size: 18)),
                  Text('${line.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(visualDensity: VisualDensity.compact, onPressed: () => changeQuantity(entry.key, 1), icon: const Icon(Icons.add_circle_outline, size: 18)),
                ]),
              ])),
              IconButton(onPressed: () => setState(() => cart.remove(entry.key)), icon: const Icon(Icons.delete_outline, color: textGray)),
            ]),
          );
        }),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            if (voucherClaimed) ...[
              Row(children: [const Expanded(child: Text('Subtotal')), Text(money(rawCartTotal), style: const TextStyle(color: textGray))]),
              const SizedBox(height: 4),
              Row(children: [const Expanded(child: Text('New User 20% Voucher', style: TextStyle(color: primaryOrange, fontWeight: FontWeight.bold))), Text('-${money(rawCartTotal * 0.2)}', style: const TextStyle(color: primaryOrange, fontWeight: FontWeight.bold))]),
              const Divider(height: 14),
            ],
            Row(children: [const Expanded(child: Text('Total Amount Due', style: TextStyle(fontWeight: FontWeight.bold))), Text(money(cartTotal), style: const TextStyle(fontWeight: FontWeight.w900, color: primaryOrange, fontSize: 16))]),
            const SizedBox(height: 14),
            ElevatedButton(onPressed: placingOrder ? null : checkout, child: const Text('PROCEED TO CHECKOUT')),
          ]),
        ),
      ],
    );
  }

  Widget _buildOrders() {
    final user = FirebaseAuth.instance.currentUser!;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('orders').where('userId', isEqualTo: user.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: primaryOrange));
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No previous orders found.', style: TextStyle(color: textGray)));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('My Orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            ...docs.map((doc) {
              final d = doc.data();
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Order #${doc.id.substring(0, 6)} (${d['paymentMethod'] ?? 'COD'})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    Text(d['status'] ?? 'Pending', style: const TextStyle(color: primaryOrange, fontWeight: FontWeight.bold, fontSize: 11)),
                  ]),
                  const Divider(height: 16),
                  Text(money(parsePrice(d['total'])), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                ]),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildProfile() {
    final user = FirebaseAuth.instance.currentUser!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: textDark, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CircleAvatar(backgroundColor: primaryOrange, child: Icon(Icons.person, color: Colors.white)),
            const SizedBox(height: 10),
            Text(user.displayName ?? 'Streetwear Member', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text(user.email ?? '', style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 14),
        ListTile(
          tileColor: cardBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: const Icon(Icons.headset_mic, color: textGray),
          title: const Text('Customer Support Chat', style: TextStyle(fontWeight: FontWeight.bold)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openCommunityChat(context),
        ),
        const SizedBox(height: 10),
        ListTile(
          tileColor: cardBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: const Icon(Icons.logout, color: textGray),
          title: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
          onTap: () async => await FirebaseAuth.instance.signOut(),
        ),
      ],
    );
  }
}

class ProductCard extends StatelessWidget {
  final Product product;
  final bool wished;
  final VoidCallback onWishlist;
  final VoidCallback onTap;
  const ProductCard({super.key, required this.product, required this.wished, required this.onWishlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              product.imageUrl.isEmpty ? const ProductPlaceholder() : Image.network(product.imageUrl, fit: BoxFit.cover),
              Positioned(
                right: 6, top: 6,
                child: InkWell(
                  onTap: onWishlist,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Colors.white70, shape: BoxShape.circle),
                    child: Icon(wished ? Icons.favorite : Icons.favorite_border, size: 16, color: wished ? primaryOrange : textDark),
                  ),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 6),
              Text(money(product.price), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: primaryOrange)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class ProductPlaceholder extends StatelessWidget {
  const ProductPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => Container(color: Colors.grey[200], child: const Center(child: Icon(Icons.checkroom, color: textGray)));
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  bool hidePassword = true;

  Future<void> login() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.text.trim(), password: password.text);
    } on FirebaseAuthException catch (e) {
      if (mounted) showMessage(context, e.message ?? 'Login failed');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resetPassword() async {
    if (email.text.trim().isEmpty) {
      showMessage(context, 'Please enter your email address above first.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.text.trim());
      if (mounted) showMessage(context, 'Password reset link sent to your email!');
    } on FirebaseAuthException catch (e) {
      if (mounted) showMessage(context, e.message ?? 'Error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: formKey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('STREETWEAR', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: primaryOrange)),
              const SizedBox(height: 8),
              const Text('Welcome back!', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 24),
              TextFormField(controller: email, decoration: const InputDecoration(labelText: 'Email Address')),
              const SizedBox(height: 12),
              TextFormField(controller: password, obscureText: hidePassword, decoration: const InputDecoration(labelText: 'Password')),
              Align(alignment: Alignment.centerRight, child: TextButton(onPressed: resetPassword, child: const Text('Forgot password?', style: TextStyle(color: primaryOrange, fontWeight: FontWeight.bold)))),
              const SizedBox(height: 10),
              ElevatedButton(onPressed: loading ? null : login, child: const Text('SIGN IN')),
              const SizedBox(height: 16),
              Center(child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                child: const Text('Don\'t have an account? Register', style: TextStyle(fontWeight: FontWeight.bold, color: primaryOrange)),
              )),
            ]),
          ),
        ),
      ),
    ),
  );
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;

  Future<void> register() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => loading = true);
    try {
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email.text.trim(), password: password.text);
      await credential.user!.updateDisplayName(name.text.trim());
      await FirebaseFirestore.instance.collection('users').doc(credential.user!.uid).set({
        'name': name.text.trim(), 'email': email.text.trim(), 'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (mounted) showMessage(context, e.message ?? 'Error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('CREATE ACCOUNT')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Form(
          key: formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Join Us Today', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 20),
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Full Name')),
            const SizedBox(height: 12),
            TextFormField(controller: email, decoration: const InputDecoration(labelText: 'Email Address')),
            const SizedBox(height: 12),
            TextFormField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: loading ? null : register, child: const Text('CREATE ACCOUNT')),
          ]),
        ),
      ),
    ),
  );
}