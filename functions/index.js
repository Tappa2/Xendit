const { initializeApp } = require("firebase-admin/app");
const {
  getFirestore,
  Timestamp,
  FieldValue,
} = require("firebase-admin/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");

initializeApp();

const db = getFirestore();
const COOLDOWN_MS = 5 * 60 * 60 * 1000;

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "Mag-login muna para magamit ang voucher at checkout."
    );
  }
  return request.auth.uid;
}

function asText(value, field, maxLength = 300) {
  if (typeof value !== "string" || !value.trim()) {
    throw new HttpsError("invalid-argument", `Kailangan ang ${field}.`);
  }
  if (value.trim().length > maxLength) {
    throw new HttpsError("invalid-argument", `Masyadong mahaba ang ${field}.`);
  }
  return value.trim();
}

// I-check ang active voucher at eligibility ng account.
exports.getVoucherStatus = onCall(async (request) => {
  const uid = requireAuth(request);
  const ref = db.collection("voucherAccounts").doc(uid);
  const snap = await ref.get();
  const data = snap.exists ? snap.data() : {};
  const now = Timestamp.now();
  const active = data.activeVoucher;

  // Ang na-claim pero hindi pa nagagamit na voucher ay mananatiling active.
  if (active && [20, 50].includes(active.percent)) {
    return {
      claimablePercent: active.percent,
      voucherType: active.type,
      activeVoucher: true,
      canClaim: false,
      nextEligibleAt: data.nextEligibleAt
        ? data.nextEligibleAt.toMillis()
        : null,
    };
  }

  if (data.newUserClaimed !== true) {
    return {
      claimablePercent: 20,
      voucherType: "NEW_USER_20",
      activeVoucher: false,
      canClaim: true,
      nextEligibleAt: null,
    };
  }

  const next = data.nextEligibleAt;

  if (!next || now.toMillis() >= next.toMillis()) {
    return {
      claimablePercent: 50,
      voucherType: "REGULAR_50",
      activeVoucher: false,
      canClaim: true,
      nextEligibleAt: next ? next.toMillis() : null,
    };
  }

  return {
    claimablePercent: 0,
    voucherType: null,
    activeVoucher: false,
    canClaim: false,
    nextEligibleAt: next.toMillis(),
  };
});

// Isang active voucher lang bawat account.
exports.claimVoucher = onCall(async (request) => {
  const uid = requireAuth(request);
  const voucherRef = db.collection("voucherAccounts").doc(uid);
  const historyRef = voucherRef.collection("history").doc();

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(voucherRef);
    const data = snap.exists ? snap.data() : {};
    const now = Timestamp.now();

    if (data.activeVoucher) {
      throw new HttpsError(
        "failed-precondition",
        "May active voucher ka pa. Gamitin muna ito sa order."
      );
    }

    let percent;
    let voucherType;

    if (data.newUserClaimed !== true) {
      percent = 20;
      voucherType = "NEW_USER_20";
    } else {
      const next = data.nextEligibleAt;

      if (next && now.toMillis() < next.toMillis()) {
        throw new HttpsError(
          "failed-precondition",
          "Hindi ka pa eligible. Hintayin ang 5-hour cooldown."
        );
      }

      percent = 50;
      voucherType = "REGULAR_50";
    }

    // Nagsisimula ang cooldown sa oras ng claim.
    const nextEligibleAt = Timestamp.fromMillis(
      now.toMillis() + COOLDOWN_MS
    );
    const claimCount = (data.claimCount || 0) + 1;

    tx.set(voucherRef, {
      newUserClaimed: true,
      activeVoucher: {
        type: voucherType,
        percent,
        claimedAt: now,
      },
      lastVoucherType: voucherType,
      lastVoucherPercent: percent,
      lastClaimAt: now,
      nextEligibleAt,
      claimCount,
      updatedAt: now,
    }, { merge: true });

    tx.set(historyRef, {
      voucherType,
      percent,
      claimedAt: now,
      nextEligibleAt,
      status: "claimed",
    });

    return {
      success: true,
      voucherType,
      percent,
      claimedAt: now.toMillis(),
      nextEligibleAt: nextEligibleAt.toMillis(),
    };
  });
});

// Server-side checkout: server ang kumukuha ng presyo sa products collection.
exports.createOrder = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = request.data || {};

  const customerName = asText(input.customerName, "pangalan", 150);
  const phone = asText(input.phone, "mobile number", 40);
  const shippingAddress = asText(input.shippingAddress, "address", 500);
  const paymentMethod = input.paymentMethod;

  if (!["Cash on Delivery", "GCash"].includes(paymentMethod)) {
    throw new HttpsError("invalid-argument", "Invalid payment method.");
  }

  if (!Array.isArray(input.items) || input.items.length === 0 ||
      input.items.length > 50) {
    throw new HttpsError("invalid-argument", "Invalid order items.");
  }

  const items = input.items.map((item) => {
    const productId = asText(item.productId, "product ID", 150);
    const quantity = item.quantity;

    if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > 20) {
      throw new HttpsError("invalid-argument", "Invalid item quantity.");
    }

    return {
      productId,
      quantity,
      size: asText(item.size, "size", 40),
      color: typeof item.color === "string" ? item.color.slice(0, 60) : "",
    };
  });

  // Isang read lang bawat product, kahit maraming size/color line.
  const quantities = new Map();
  for (const item of items) {
    quantities.set(
      item.productId,
      (quantities.get(item.productId) || 0) + item.quantity
    );
  }

  const productRefs = new Map(
    [...quantities.keys()].map((id) => [
      id,
      db.collection("products").doc(id),
    ])
  );

  const voucherRef = db.collection("voucherAccounts").doc(uid);
  const orderRef = db.collection("orders").doc();

  return db.runTransaction(async (tx) => {
    // Lahat ng reads ay nauuna sa writes.
    const voucherSnap = await tx.get(voucherRef);
    const productDocs = new Map();

    for (const [id, ref] of productRefs) {
      productDocs.set(id, await tx.get(ref));
    }

    const now = Timestamp.now();
    const voucherData = voucherSnap.exists ? voucherSnap.data() : {};
    const active = voucherData.activeVoucher;

    const orderItems = [];
    let subtotalCents = 0;

    for (const item of items) {
      const productSnap = productDocs.get(item.productId);

      if (!productSnap.exists) {
        throw new HttpsError(
          "failed-precondition",
          "May produktong wala na sa store. I-refresh ang cart."
        );
      }

      const product = productSnap.data();
      const price = Number(product.price);
      const stock = Number.isInteger(product.stock) ? product.stock : 99;

      if (!Number.isFinite(price) || price < 0) {
        throw new HttpsError(
          "failed-precondition",
          "May invalid na presyo sa product catalog."
        );
      }

      if (!Array.isArray(product.sizes) ||
          !product.sizes.includes(item.size)) {
        throw new HttpsError(
          "failed-precondition",
          "Hindi available ang napiling size. I-refresh ang cart."
        );
      }

      if (Array.isArray(product.colors) &&
          product.colors.length > 0 &&
          !product.colors.includes(item.color)) {
        throw new HttpsError(
          "failed-precondition",
          "Hindi available ang napiling color. I-refresh ang cart."
        );
      }

      const unitPriceCents = Math.round(price * 100);
      const lineCents = unitPriceCents * item.quantity;
      subtotalCents += lineCents;

      orderItems.push({
        productId: item.productId,
        name: String(product.name || "Streetwear Item"),
        imageUrl: String(product.imageUrl || product.imageURL || ""),
        unitPrice: unitPriceCents / 100,
        quantity: item.quantity,
        size: item.size,
        color: item.color,
        subtotal: lineCents / 100,
      });
    }

    for (const [id] of productRefs) {
      const product = productDocs.get(id).data();
      const stock = Number.isInteger(product.stock) ? product.stock : 99;

      if (stock < quantities.get(id)) {
        throw new HttpsError(
          "failed-precondition",
          "Kulang ang stock para sa isa o higit pang produkto."
        );
      }
    }

    let voucherPercent = 0;
    let voucherType = null;

    if (active) {
      if (![20, 50].includes(active.percent) ||
          !["NEW_USER_20", "REGULAR_50"].includes(active.type)) {
        throw new HttpsError(
          "failed-precondition",
          "Invalid ang voucher record. Makipag-ugnayan sa store."
        );
      }
      voucherPercent = active.percent;
      voucherType = active.type;
    }

    const discountCents = Math.round(
      subtotalCents * voucherPercent / 100
    );
    const totalCents = Math.max(0, subtotalCents - discountCents);

    // I-reserve ang stock sa parehong transaction ng order.
    for (const [id, ref] of productRefs) {
      const product = productDocs.get(id).data();
      const stock = Number.isInteger(product.stock) ? product.stock : 99;

      tx.update(ref, {
        stock: stock - quantities.get(id),
        updatedAt: now,
      });
    }

    tx.create(orderRef, {
      userId: uid,
      userEmail: request.auth.token.email || "",
      customerName,
      phone,
      shippingAddress,
      items: orderItems,
      subtotal: subtotalCents / 100,
      discount: discountCents / 100,
      total: totalCents / 100,
      voucherApplied: voucherPercent > 0,
      voucherType,
      voucherPercent,
      status: "Pending",
      paymentMethod,
      // GCash remains unverified until a real payment provider confirms it.
      paymentStatus: paymentMethod === "GCash"
        ? "Pending"
        : "Cash on Delivery",
      createdAt: now,
      updatedAt: now,
    });

    if (active) {
      tx.update(voucherRef, {
        activeVoucher: FieldValue.delete(),
        lastUsedAt: now,
        lastOrderId: orderRef.id,
        updatedAt: now,
      });

      tx.set(
        voucherRef.collection("history").doc(),
        {
          voucherType,
          percent: voucherPercent,
          status: "used",
          orderId: orderRef.id,
          usedAt: now,
        }
      );
    }

    return {
      success: true,
      orderId: orderRef.id,
      subtotal: subtotalCents / 100,
      discount: discountCents / 100,
      total: totalCents / 100,
      voucherType,
      voucherPercent,
      paymentStatus: paymentMethod === "GCash" ? "Pending" : "Cash on Delivery",
    };
  });
});
