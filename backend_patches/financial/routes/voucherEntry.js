import express from "express";
import pool from "../db.js";
import requireAuth from "../middleware/requireAuth.js";
import { createMobileNotificationForAdmin } from "../utils/mobileNotification.js";
import { grossAmount, hasCashFlowColumns } from "../utils/cashFlowColumns.js";

const router = express.Router();

/**
 * A ledger name as Tally compares it: capitals ignored, line breaks and
 * repeated spaces = one space. Voucher lines and ledger masters can spell
 * the same ledger differently ("DAIKIN  AIR…" vs "DAIKIN AIR…").
 */
const NAME_KEY = (col) => `lower(btrim(regexp_replace(${col}, '[[:space:]]+', ' ', 'g')))`;

/* =====================================================
   MARK INACTIVE VOUCHERS
===================================================== */
router.post("/reset-active", requireAuth, async (req, res) => {
  const adminId = req.user.adminId;
  const { company_guid } = req.body;

  if (!adminId || !company_guid) {
    return res.status(400).json({ success: false });
  }

  try {
    await pool.query(
      `
      UPDATE vouchers
      SET is_active = false
      WHERE admin_id = $1
        AND company_guid = $2
      `,
      [adminId, company_guid]
    );

    await pool.query(
      `
      UPDATE voucher_entries
      SET is_active = false
      WHERE admin_id = $1
        AND company_guid = $2
      `,
      [adminId, company_guid]
    );

    res.json({ success: true });
  } catch (err) {
    console.error("Reset active failed:", err.message);
    res.status(500).json({ success: false });
  }
});




/* =====================================================
   SYNC VOUCHER ENTRIES
===================================================== */
router.post("/sync", requireAuth, async (req, res) => {
  const adminId = req.user.adminId;

  const {
    voucher_guid,
    company_guid,
    voucher_date,
    voucher_type,
    reference_no,
    net_amount,        // ✅ MUST ADD THIS
    party_name, 
    entries,
    has_cash_flow,
  } = req.body;
  // Tally's Cash Flow flag of the voucher (true / false); an Agent without
  // it sends nothing, and what is stored is kept.
  const cashFlowFlag = typeof has_cash_flow === "boolean" ? has_cash_flow : null;

  // ✅ ADD THIS BLOCK HERE
const companyCheck = await pool.query(
  `
  SELECT 1 FROM companies
  WHERE company_guid = $1 AND admin_id = $2
  `,
  [company_guid, adminId]
);

if (companyCheck.rowCount === 0) {
  console.log("⛔ Voucher skipped (company not owned):", company_guid);

  return res.json({
    success: true,
    skipped: true
  });
}


  if (!adminId || !voucher_guid || !company_guid || !Array.isArray(entries)) {
    return res.status(400).json({ success: false });
  }

  // The Cash Flow columns (flag, a line's gross Dr / Cr) once the database
  // has them; before that the sync stores exactly what it did.
  const cf = await hasCashFlowColumns(pool);

  const client = await pool.connect();

  try {
    await client.query("BEGIN");

    /* ==============================
       1️⃣ UPSERT INTO vouchers
    ============================== */
await client.query(
      `
      INSERT INTO vouchers (
        admin_id,
        voucher_guid,
        company_guid,
        voucher_type,
        voucher_date,
        reference_no,
        net_amount,
        party_name,
        ${cf ? "has_cash_flow," : ""}
        is_active
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,${cf ? "$9," : ""}true)
      ON CONFLICT (admin_id, company_guid, voucher_guid)
      DO UPDATE SET
        voucher_type = EXCLUDED.voucher_type,
        voucher_date = EXCLUDED.voucher_date,
        reference_no = EXCLUDED.reference_no,
        net_amount = EXCLUDED.net_amount,
        party_name = EXCLUDED.party_name,
        ${cf ? "has_cash_flow = COALESCE(EXCLUDED.has_cash_flow, vouchers.has_cash_flow)," : ""}
        is_active = true
      `,
      [
        adminId,
        voucher_guid,
        company_guid,
        voucher_type,
        voucher_date,
        reference_no,
        net_amount || 0,
        party_name || null,
        ...(cf ? [cashFlowFlag] : []),
      ]
    );

    /* ==============================
       2️⃣ UPSERT voucher_entries
    ============================== */
    for (const e of entries) {
      if (!e.ledger_name || e.amount === undefined || e.is_debit === undefined) {
        continue;
      }

      await client.query(
        `
        INSERT INTO voucher_entries (
          admin_id,
          voucher_guid,
          company_guid,
          ledger_name,
          amount,
          is_debit,
          voucher_date,
          voucher_type,
          reference_no,
          ${cf ? "gross_dr, gross_cr," : ""}
          is_active
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,${cf ? "$10,$11," : ""}true)
        ON CONFLICT (admin_id, company_guid, voucher_guid, ledger_name)
        DO UPDATE SET
          amount = EXCLUDED.amount,
          is_debit = EXCLUDED.is_debit,
          voucher_date = EXCLUDED.voucher_date,
          voucher_type = EXCLUDED.voucher_type,
          reference_no = EXCLUDED.reference_no,
          ${cf ? "gross_dr = EXCLUDED.gross_dr, gross_cr = EXCLUDED.gross_cr," : ""}
          is_active = true
        `,
        [
          adminId,
          voucher_guid,
          company_guid,
          e.ledger_name,
          Math.abs(e.amount),
          e.is_debit,
          voucher_date,
          voucher_type,
          reference_no,
          ...(cf ? [grossAmount(e.gross_dr), grossAmount(e.gross_cr)] : []),
        ]
      );
    }

    /* ==============================
       3️⃣ Lines no longer in this voucher → inactive
       A line stored earlier but not sent now (the voucher was edited in
       Tally, or the ledger was stored under another spelling) would else
       stay counted. Only this voucher, this company, this account; only
       when the payload carries the voucher's real lines (a lone zero
       placeholder means Tally sent no lines — what is stored is kept).
    ============================== */
    const sentLines = entries.filter(
      (e) => e && e.ledger_name && e.amount !== undefined && e.is_debit !== undefined
    );
    if (sentLines.some((e) => Number(e.amount) !== 0)) {
      await client.query(
        `
        UPDATE voucher_entries
        SET is_active = false
        WHERE admin_id = $1
          AND company_guid = $2
          AND voucher_guid = $3
          AND is_active IS DISTINCT FROM false
          AND NOT (ledger_name = ANY($4::text[]))
        `,
        [adminId, company_guid, voucher_guid, sentLines.map((e) => e.ledger_name)]
      );
    }

    await client.query("COMMIT");
    createMobileNotificationForAdmin({
      type: "voucher_sync",
      message: `${voucher_type} | ₹${Number(net_amount || 0)} | ${party_name || "-"} | synced from Tally`,
      adminId,
      meta: {
        voucher_guid,
        company_guid,
        voucher_type,
        reference_no,
        voucher_date,
        party_name: party_name || null,
        amount: Number(net_amount || 0)
      }
    }).catch((e) => console.error("mobile voucher_sync notify error:", e.message));

    res.json({ success: true });

  } catch (err) {
  await client.query("ROLLBACK");

  console.error("Voucher sync error:", err.message);

  // ✅ DO NOT BREAK SYNC
  return res.json({
    success: true,
    skipped: true
  });
} finally {
    client.release();
  }
});


/* =====================================================
   GET VOUCHERS (UI)
===================================================== */
router.get("/", requireAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const role = req.user.role;
    const adminId = req.user.adminId;
    const { ledgerGuid } = req.query;

    /* ========= LEDGER DETAIL MODE ========= */
    if (ledgerGuid) {
      if (role !== "ADMIN") {
        const check = await pool.query(
  `
  SELECT 1
  FROM user_ledger_permissions ulp
  JOIN ledgers l
    ON l.ledger_guid = ulp.ledger_guid
  WHERE ulp.user_id = $1
    AND ulp.ledger_guid = $2
    AND l.admin_id = $3
  `,
  [userId, ledgerGuid, adminId]
);


        if (check.rowCount === 0) {
          return res.status(403).json({ message: "Access denied" });
        }
      }

      const result = await pool.query(
        `
        SELECT
          ve.voucher_guid AS id,
          ve.voucher_date,
          ve.voucher_type,
          ve.reference_no,
          CASE WHEN ve.is_debit THEN ve.amount ELSE 0 END AS debit,
          CASE WHEN NOT ve.is_debit THEN ve.amount ELSE 0 END AS credit
        FROM voucher_entries ve
        JOIN ledgers l
  ON l.ledger_guid = $1
 AND l.company_guid = ve.company_guid
 AND l.admin_id = $2
 AND ${NAME_KEY("ve.ledger_name")} = ${NAME_KEY("l.name")}

        WHERE ve.is_active = true
          AND ve.admin_id = $2
          AND ve.company_guid = (
            SELECT company_guid
            FROM active_company
            WHERE admin_id = $2
          )
        ORDER BY ve.voucher_date ASC
        `,
        [ledgerGuid, adminId]
      );

      return res.json(result.rows);
    }

    /* ========= VOUCHER LIST ========= */
    let query;
    let params;

    if (role === "ADMIN") {
      query = `
SELECT
  v.voucher_guid,
  v.company_guid,
  v.voucher_date,
  v.voucher_type,
  v.reference_no,
  v.net_amount AS amount,
  v.is_active,
  v.party_name
FROM vouchers v
WHERE v.admin_id = $1
  AND v.company_guid = (
    SELECT company_guid
    FROM active_company
    WHERE admin_id = $1
  )
ORDER BY v.voucher_date DESC
`;
      params = [adminId];
    } else {
      query = `
SELECT
  v.voucher_guid,
  v.company_guid,
  v.voucher_date,
  v.voucher_type,
  v.reference_no,
  v.net_amount AS amount,
  v.is_active,
  v.party_name
FROM vouchers v
JOIN users u ON u.id = $1
WHERE v.admin_id = u.admin_id
  AND v.company_guid = (
    SELECT company_guid
    FROM active_company
    WHERE admin_id = u.admin_id
  )
  AND v.voucher_guid = ANY (
    SELECT jsonb_array_elements_text(
      u.voucher_selection_permissions->'allowed_vouchers'
    )
  )
ORDER BY v.voucher_date DESC
`;
      params = [userId];
    }

    const result = await pool.query(query, params);
    const rows = result.rows;

    if (rows.length > 0) {
      const voucherGuids = rows.map((r) => r.voucher_guid);

      /* party_name fallback */
      const partyRes = await pool.query(
        `
        SELECT
          ve.voucher_guid,
          MAX(CASE WHEN ve.is_debit = false THEN ve.ledger_name END) AS party_name
        FROM voucher_entries ve
        WHERE ve.admin_id = $1
          AND ve.voucher_guid = ANY($2)
        GROUP BY ve.voucher_guid
        `,
        [adminId, voucherGuids]
      );
      const partyMap = new Map(partyRes.rows.map((p) => [p.voucher_guid, p.party_name]));
      for (const r of rows) {
        if (!r.party_name) r.party_name = partyMap.get(r.voucher_guid) ?? null;
      }

      /* items batch */
      const itemRes = await pool.query(
        `
        SELECT voucher_guid, item_name, quantity, rate, amount
        FROM ledger_items
        WHERE admin_id = $1
          AND voucher_guid = ANY($2)
        `,
        [adminId, voucherGuids]
      );
      const itemMap = new Map();
      for (const it of itemRes.rows) {
        if (!itemMap.has(it.voucher_guid)) itemMap.set(it.voucher_guid, []);
        itemMap.get(it.voucher_guid).push({
          item_name: it.item_name,
          quantity: it.quantity,
          rate: it.rate,
          amount: it.amount
        });
      }
      for (const r of rows) r.items = itemMap.get(r.voucher_guid) ?? [];
    }

    res.json({ success: true, data: rows });
  } catch (err) {
    console.error("Voucher GET error:", err);
    res.status(500).json({ success: false });
  }
});

/* =====================================================
   GET VOUCHERS PAGED (UI - fast list / infinite scroll)
   IMPORTANT: registered BEFORE the /:voucherGuid route
===================================================== */
router.get("/paged", requireAuth, async (req, res) => {
  try {
    const userId = req.user.id;
    const role = req.user.role;
    const adminId = req.user.adminId;

    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(200, Math.max(1, parseInt(req.query.limit, 10) || 50));
    const offset = (page - 1) * limit;

    const type = req.query.type?.trim();
    const search = req.query.search?.trim();

    const parsedYear = parseInt(req.query.year, 10);
    const year = Number.isNaN(parsedYear) ? null : parsedYear;

    const parsedMonth = parseInt(req.query.month, 10);
    const month = Number.isNaN(parsedMonth) ? null : parsedMonth;

    const orderByMap = {
      date_desc: "v.voucher_date DESC, v.voucher_guid DESC",
      date_asc: "v.voucher_date ASC, v.voucher_guid ASC",
      amount_desc: "COALESCE(v.net_amount, 0) DESC, v.voucher_date DESC",
      amount_asc: "COALESCE(v.net_amount, 0) ASC, v.voucher_date DESC"
    };
    const orderBySql = orderByMap[req.query.sort_by] || orderByMap.date_desc;

    const params = [];
    if (role === "ADMIN") params.push(adminId);
    else params.push(userId);
    const baseParamCount = params.length;

    const baseClauses = [];
    const filterClauses = [];

    if (role === "ADMIN") {
      baseClauses.push("v.admin_id = $1");
      baseClauses.push(
        "v.company_guid = (SELECT company_guid FROM active_company WHERE admin_id = $1)"
      );
    } else {
      baseClauses.push("v.admin_id = u.admin_id");
      baseClauses.push(
        "v.company_guid = (SELECT company_guid FROM active_company WHERE admin_id = u.admin_id)"
      );
      baseClauses.push(
        "v.voucher_guid = ANY (SELECT jsonb_array_elements_text(u.voucher_selection_permissions->'allowed_vouchers'))"
      );
    }

    if (type) {
      params.push(type);
      filterClauses.push(`v.voucher_type ILIKE '%' || $${params.length} || '%'`);
    }
    if (search) {
      params.push(search);
      const i = params.length;
      filterClauses.push(
        `(v.party_name ILIKE '%' || $${i} || '%' ` +
          `OR v.reference_no ILIKE '%' || $${i} || '%' ` +
          `OR v.voucher_type ILIKE '%' || $${i} || '%' ` +
          `OR v.voucher_date::text ILIKE '%' || $${i} || '%')`
      );
    }
    if (year) {
      params.push(year);
      filterClauses.push(`EXTRACT(YEAR FROM v.voucher_date) = $${params.length}`);
    }
    if (month) {
      params.push(month);
      filterClauses.push(`EXTRACT(MONTH FROM v.voucher_date) = $${params.length}`);
    }

    const joinSql = role === "ADMIN" ? "" : "JOIN users u ON u.id = $1";
    const allClauses = [...baseClauses, ...filterClauses];
    const whereSql = allClauses.length ? `WHERE ${allClauses.join(" AND ")}` : "";
    const baseWhereSql = `WHERE ${baseClauses.join(" AND ")}`;

    const countRes = await pool.query(
      `SELECT COUNT(*)::int AS total FROM vouchers v ${joinSql} ${whereSql}`,
      params
    );
    const total = countRes.rows[0]?.total ?? 0;

    const sumRes = await pool.query(
      `SELECT COALESCE(SUM(COALESCE(v.net_amount, 0)), 0) AS total_amount FROM vouchers v ${joinSql} ${whereSql}`,
      params
    );
    const totalAmount = Number(sumRes.rows[0]?.total_amount ?? 0);

    let typesList = [];
    let yearsList = [];
    if (total > 0) {
      const typesRes = await pool.query(
        `SELECT DISTINCT v.voucher_type AS type
         FROM vouchers v ${joinSql} ${baseWhereSql}
           AND v.voucher_type IS NOT NULL AND v.voucher_type <> ''
         ORDER BY v.voucher_type ASC`,
        params.slice(0, baseParamCount)
      );
      typesList = typesRes.rows.map((r) => r.type);

      const yearsRes = await pool.query(
        `SELECT DISTINCT EXTRACT(YEAR FROM v.voucher_date)::int AS year
         FROM vouchers v ${joinSql} ${baseWhereSql}
           AND v.voucher_date IS NOT NULL
         ORDER BY year DESC`,
        params.slice(0, baseParamCount)
      );
      yearsList = yearsRes.rows.map((r) => r.year);
    }

    const rowsRes = await pool.query(
      `SELECT
        v.voucher_guid,
        v.company_guid,
        v.voucher_date,
        v.voucher_type,
        v.reference_no,
        v.net_amount AS amount,
        v.is_active,
        v.party_name
       FROM vouchers v ${joinSql} ${whereSql}
       ORDER BY ${orderBySql}
       LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
      [...params, limit, offset]
    );
    const rows = rowsRes.rows;

    if (rows.length > 0) {
      const voucherGuids = rows.map((r) => r.voucher_guid);

      const partyRes = await pool.query(
        `
        SELECT
          ve.voucher_guid,
          MAX(CASE WHEN ve.is_debit = false THEN ve.ledger_name END) AS party_name
        FROM voucher_entries ve
        WHERE ve.admin_id = $1
          AND ve.voucher_guid = ANY($2)
        GROUP BY ve.voucher_guid
        `,
        [adminId, voucherGuids]
      );
      const partyMap = new Map(partyRes.rows.map((p) => [p.voucher_guid, p.party_name]));
      for (const r of rows) {
        if (!r.party_name) r.party_name = partyMap.get(r.voucher_guid) ?? null;
      }

      const itemRes = await pool.query(
        `
        SELECT voucher_guid, item_name, quantity, rate, amount
        FROM ledger_items
        WHERE admin_id = $1
          AND voucher_guid = ANY($2)
        `,
        [adminId, voucherGuids]
      );
      const itemMap = new Map();
      for (const it of itemRes.rows) {
        if (!itemMap.has(it.voucher_guid)) itemMap.set(it.voucher_guid, []);
        itemMap.get(it.voucher_guid).push({
          item_name: it.item_name,
          quantity: it.quantity,
          rate: it.rate,
          amount: it.amount
        });
      }
      for (const r of rows) r.items = itemMap.get(r.voucher_guid) ?? [];
    }

    res.json({
      success: true,
      data: rows,
      meta: {
        total,
        page,
        limit,
        hasMore: offset + rows.length < total,
        totalAmount,
        types: typesList,
        years: yearsList
      }
    });
  } catch (err) {
    console.error("Voucher paged GET error:", err);
    res.status(500).json({ success: false });
  }
});

/* =====================================================
   DELETE (SOFT DELETE) VOUCHER
===================================================== */
router.delete("/:voucherGuid", requireAuth, async (req, res) => {
  const { voucherGuid } = req.params;
  const adminId = req.user.adminId;

  try {
   await pool.query(
  `
  UPDATE vouchers
  SET is_active = false
  WHERE admin_id = $1
    AND voucher_guid = $2
    AND company_guid = (
      SELECT company_guid
      FROM active_company
      WHERE admin_id = $1
    )
  `,
  [adminId, voucherGuid]
);


    res.json({ success: true });
  } catch (err) {
    console.error("Delete voucher error:", err.message);
    res.status(500).json({ success: false });
  }
});

/* =====================================================
   GET SINGLE VOUCHER (EDIT)
===================================================== */
router.get("/:voucherGuid", requireAuth, async (req, res) => {
  const { voucherGuid } = req.params;
  const adminId = req.user.adminId;

  const result = await pool.query(
    `
    SELECT
      voucher_guid,
      voucher_date,
      voucher_type,
      reference_no,
      ledger_name,
      amount,
      is_debit
    FROM voucher_entries
    WHERE admin_id = $1
      AND company_guid = (
        SELECT company_guid
        FROM active_company
        WHERE admin_id = $1
      )
      AND voucher_guid = $2
      AND is_active = true
    ORDER BY is_debit DESC
    `,
    [adminId, voucherGuid]
  );

  if (result.rowCount === 0) {
    return res.status(404).json({ message: "Voucher not found" });
  }

  const rows = result.rows;

  res.json({
    voucher_guid: rows[0].voucher_guid,
    voucher_date: rows[0].voucher_date,
    voucher_type: rows[0].voucher_type,
    reference_no: rows[0].reference_no,
    ledger_entries: rows.map(r => ({
      ledger_name: r.ledger_name,
      amount: Number(r.amount),
      is_debit: r.is_debit
    }))
  });
});


router.get("/user-vouchers/:userId", requireAuth, async (req, res) => {
  const { userId } = req.params;

  try {
    const result = await pool.query(
      `SELECT voucher_selection_permissions
       FROM users
       WHERE id = $1`,
      [userId]
    );

    if (!result.rows.length) {
      return res.json({ vouchers: [] });
    }

    const permissions = result.rows[0].voucher_selection_permissions || {};
    const vouchers = permissions.allowed_vouchers || [];

    res.json({ vouchers });
  } catch (err) {
    console.error("Get user vouchers error:", err);
    res.status(500).json({ vouchers: [] });
  }
});

router.post("/user-vouchers", requireAuth, async (req, res) => {
  const { userId, vouchers } = req.body;

  if (!userId || !Array.isArray(vouchers)) {
    return res.status(400).json({ success: false });
  }

  try {
    await pool.query(
      `
      UPDATE users
      SET voucher_selection_permissions = jsonb_build_object(
        'allowed_vouchers', $1::jsonb
      )
      WHERE id = $2
      `,
      [JSON.stringify(vouchers), userId]
    );

    res.json({ success: true });
  } catch (err) {
    console.error("Save user vouchers error:", err);
    res.status(500).json({ success: false });
  }
});

/* =====================================================
   GET VOUCHERS BY LEDGER (Ledger Details Page)
===================================================== */
// router.get("/ledger/:ledgerGuid", requireAuth, async (req, res) => {

//   const { ledgerGuid } = req.params;
//   const adminId = req.user.adminId;
//   const role = req.user.role;
//   const userId = req.user.id;

//   try {
//     /* =========================
//        🔐 Permission Check
//     ========================== */
//     if (role !== "ADMIN") {
//       const check = await pool.query(
//         `
//         SELECT 1
//         FROM user_ledger_permissions ulp
//         JOIN ledgers l
//           ON l.ledger_guid = ulp.ledger_guid
//         WHERE ulp.user_id = $1
//           AND ulp.ledger_guid = $2
//           AND l.admin_id = $3
//         `,
//         [userId, ledgerGuid, adminId]
//       );

//       if (check.rowCount === 0) {
//         return res.status(403).json({ message: "Access denied" });
//       }
//     }

//     /* =========================
//        🎯 Fetch Only That Ledger's Entries
//     ========================== */
//     const result = await pool.query(
//       `
//       SELECT
//   ve.voucher_guid AS id,
//   MAX(ve.voucher_date) AS voucher_date,
//   MAX(ve.voucher_type) AS voucher_type,
//   MAX(ve.reference_no) AS reference_no,

//   SUM(CASE WHEN ve.is_debit THEN ve.amount ELSE 0 END) AS debit,
//   SUM(CASE WHEN NOT ve.is_debit THEN ve.amount ELSE 0 END) AS credit

// FROM voucher_entries ve
// JOIN ledgers l
//   ON l.ledger_guid = $1
//  AND l.admin_id = $2
//  AND l.company_guid = ve.company_guid
//  AND ve.ledger_name = l.name

// WHERE ve.is_active = true
//   AND ve.company_guid = (
//     SELECT company_guid
//     FROM active_company
//     WHERE admin_id = $2
//   )

// GROUP BY ve.voucher_guid
// ORDER BY MAX(ve.voucher_date) ASC
//       `,
//       [ledgerGuid, adminId]
//     );

//     res.json(result.rows);

//   } catch (err) {
//     console.error("Ledger vouchers fetch error:", err);
//     res.status(500).json({ message: "Failed to fetch ledger vouchers" });
//   }
// });


// New
router.get("/ledger/:ledgerGuid", requireAuth, async (req, res) => {

  const { ledgerGuid } = req.params;
  const adminId = req.user.adminId;
  const role = req.user.role;
  const userId = req.user.id;

  try {
    /* 🔐 Permission Check (unchanged) */
    if (role !== "ADMIN") {
      const check = await pool.query(
        `
        SELECT 1
        FROM user_ledger_permissions ulp
        JOIN ledgers l
          ON l.ledger_guid = ulp.ledger_guid
        WHERE ulp.user_id = $1
          AND ulp.ledger_guid = $2
          AND l.admin_id = $3
        `,
        [userId, ledgerGuid, adminId]
      );

      if (check.rowCount === 0) {
        return res.status(403).json({ message: "Access denied" });
      }
    }

    /* 🎯 Fetch Only That Ledger's Entries (unchanged query) */
    const result = await pool.query(
      `
      SELECT
        ve.voucher_guid AS id,
        MAX(ve.voucher_date) AS voucher_date,
        MAX(ve.voucher_type) AS voucher_type,
        MAX(ve.reference_no) AS reference_no,
        SUM(CASE WHEN ve.is_debit THEN ve.amount ELSE 0 END) AS debit,
        SUM(CASE WHEN NOT ve.is_debit THEN ve.amount ELSE 0 END) AS credit
      FROM voucher_entries ve
      JOIN ledgers l
        ON l.ledger_guid = $1
       AND l.admin_id = $2
       AND l.company_guid = ve.company_guid
       AND ${NAME_KEY("ve.ledger_name")} = ${NAME_KEY("l.name")}
      WHERE ve.is_active = true
        AND ve.admin_id = $2
        AND ve.company_guid = (
          SELECT company_guid
          FROM active_company
          WHERE admin_id = $2
        )
      GROUP BY ve.voucher_guid
      ORDER BY MAX(ve.voucher_date) ASC
      `,
      [ledgerGuid, adminId]
    );

    /* 🆕 Attach items per voucher (exact join on voucher_guid) */
    let itemRows = [];
    const voucherGuids = result.rows.map((r) => r.id);

    if (voucherGuids.length > 0) {
      const itemRes = await pool.query(
        `
        SELECT
          voucher_guid,
          item_name,
          SUM(quantity) AS total_qty,
          SUM(amount)   AS total_amount
        FROM ledger_items
        WHERE admin_id = $1
          AND voucher_guid = ANY($2)
        GROUP BY voucher_guid, item_name
        `,
        [adminId, voucherGuids]
      );
      itemRows = itemRes.rows;
    }

    const data = result.rows.map((v) => ({
      ...v,
      items: itemRows.filter((i) => i.voucher_guid === v.id)
    }));

    res.json(data);

  } catch (err) {
    console.error("Ledger vouchers fetch error:", err);
    res.status(500).json({ message: "Failed to fetch ledger vouchers" });
  }
});


router.post("/bulk-user-vouchers", requireAuth, async (req, res) => {
  const { userIds, vouchers } = req.body;

  if (!Array.isArray(userIds) || !Array.isArray(vouchers)) {
    return res.status(400).json({ success: false });
  }

  try {
    await pool.query(
      `
      UPDATE users
      SET voucher_selection_permissions = jsonb_build_object(
        'allowed_vouchers', $1::jsonb
      )
      WHERE id = ANY($2)
      `,
      [JSON.stringify(vouchers), userIds]
    );

    res.json({ success: true });
  } catch (err) {
    console.error("Bulk voucher selection error:", err);
    res.status(500).json({ success: false });
  }
});


router.post("/cleanup/voucher", requireAuth, async (req, res) => {

  const { company_guid, existing_ids } = req.body;
  const adminId = req.user.adminId;

  if (!company_guid || !Array.isArray(existing_ids)) {
    return res.status(400).json({ error: "Invalid payload" });
  }

  try {

    const toDelete = await pool.query(
      `
      SELECT *
FROM vouchers
WHERE admin_id = $1
AND company_guid = $2
AND NOT (voucher_guid = ANY($3))
      `,
      [adminId, company_guid, existing_ids]
    );

    const vouchers = toDelete.rows;

    if (vouchers.length === 0) {
      return res.json({ success: true, deleted: 0 });
    }

    const voucherGuids = vouchers.map(v => v.voucher_guid);

    /* Save history */
    for (const voucher of vouchers) {

      const entries = await pool.query(
  `
  SELECT *
  FROM voucher_entries
  WHERE voucher_guid = $1
  AND admin_id = $2
  AND company_guid = $3
  `,
  [voucher.voucher_guid, adminId, company_guid]
);

      await pool.query(
        `
        INSERT INTO deleted_records
        (admin_id, company_guid, entity_type, entity_guid, entity_data, deleted_from)
        VALUES ($1,$2,$3,$4,$5,$6)
        `,
        [
          adminId,
          company_guid,
          "voucher",
          voucher.voucher_guid,
          {
            voucher,
            entries: entries.rows
          },
          "tally_sync"
        ]
      );
    }

    /* delete entries */
    await pool.query(
      `
      DELETE FROM voucher_entries
      WHERE admin_id = $2
        AND company_guid = $3
        AND voucher_guid = ANY($1)
      `,
      [voucherGuids, adminId, company_guid]
    );

    /* delete vouchers */
    const result = await pool.query(
      `
      DELETE FROM vouchers
      WHERE admin_id = $1
        AND company_guid = $2
        AND voucher_guid = ANY($3)
      `,
      [adminId, company_guid, voucherGuids]
    );

    res.json({
      success: true,
      deleted: result.rowCount
    });

  } catch (err) {
    console.error("Voucher cleanup failed:", err);
    res.status(500).json({ error: err.message });
  }

});

router.post("/deleted/restore-voucher/:id", requireAuth, async (req, res) => {

  const adminId = req.user.adminId;
  const { id } = req.params;

  const record = await pool.query(
    `
    SELECT *
    FROM deleted_records
    WHERE id=$1
      AND admin_id=$2
      AND entity_type='voucher'
    `,
    [id, adminId]
  );

  if (!record.rows.length) {
    return res.status(404).json({ error: "Record not found" });
  }

  const data = record.rows[0].entity_data;
  const voucher = data.voucher;
  const entries = data.entries;

  await pool.query(
    `
    INSERT INTO vouchers
    (
      admin_id,
      voucher_guid,
      company_guid,
      voucher_type,
      voucher_date,
      reference_no,
      net_amount,
      is_active
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,true)
    `,
    [
      voucher.admin_id,
      voucher.voucher_guid,
      voucher.company_guid,
      voucher.voucher_type,
      voucher.voucher_date,
      voucher.reference_no,
      voucher.net_amount
    ]
  );

  for (const e of entries) {

    await pool.query(
      `
      INSERT INTO voucher_entries
      (
        admin_id,
        voucher_guid,
        company_guid,
        ledger_name,
        amount,
        is_debit,
        voucher_date,
        voucher_type,
        reference_no,
        is_active
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,true)
      `,
      [
        e.admin_id,
        e.voucher_guid,
        e.company_guid,
        e.ledger_name,
        e.amount,
        e.is_debit,
        e.voucher_date,
        e.voucher_type,
        e.reference_no
      ]
    );

  }

  await pool.query(
    `DELETE FROM deleted_records WHERE id=$1`,
    [id]
  );

  res.json({
    success: true,
    message: "Voucher restored"
  });

});


export default router;
