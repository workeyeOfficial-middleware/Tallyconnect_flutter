-- E-invoice / e-way bill status (Basic): the e-invoice details Tally saved
-- on each sales invoice (IRN, acknowledgement, signed QR, e-way bill), sent
-- by the Agent beside the normal voucher sync. Run once, before deploying
-- the backend that has /api/einvoice/*. Only creates one new table; nothing
-- existing changes.

CREATE TABLE IF NOT EXISTS einvoices (
  admin_id           BIGINT        NOT NULL,
  company_guid       VARCHAR(100)  NOT NULL,
  voucher_guid       VARCHAR(120)  NOT NULL,
  voucher_date       DATE          NOT NULL,
  voucher_type       VARCHAR(120),
  voucher_no         VARCHAR(120),
  party_name         VARCHAR(255),
  party_gstin        VARCHAR(20),
  registration_type  VARCHAR(60),
  company_gstin      VARCHAR(20),
  place_of_supply    VARCHAR(80),
  amount             NUMERIC(18,2),
  -- The customer is debited (a sale / debit note), not a purchase.
  is_sale            BOOLEAN       NOT NULL DEFAULT FALSE,
  -- Tally's own marks: optional (e.g. proforma), cancelled, GST applicable.
  is_optional        BOOLEAN       NOT NULL DEFAULT FALSE,
  is_cancelled       BOOLEAN       NOT NULL DEFAULT FALSE,
  gst_applicable     BOOLEAN,
  irn                VARCHAR(64),
  ack_no             VARCHAR(30),
  ack_date           DATE,
  signed_qr          TEXT,
  irn_cancelled      BOOLEAN       NOT NULL DEFAULT FALSE,
  eway_applicable    BOOLEAN,
  -- E-way bill details as Tally sends them (field names still to be
  -- confirmed on a company that ships goods).
  eway               JSONB,
  synced_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  PRIMARY KEY (admin_id, company_guid, voucher_guid)
);

CREATE INDEX IF NOT EXISTS einvoices_date_idx ON einvoices (admin_id, company_guid, voucher_date);
