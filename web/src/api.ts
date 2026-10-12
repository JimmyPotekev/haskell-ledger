const BASE_URL = "http://localhost:3000";

// -- Types --

export interface Account {
  id: number;
  name: string;
}

export interface TransferEntry {
  account: number;
  amount: number; // integer cents
}

export interface TransferResult {
  transaction_id: number;
}

export interface BalanceResult {
  account_id: number;
  balance: number; // integer cents
}

export interface HistoryEntry {
  transaction_id: number;
  amount: number; // integer cents
}

export interface Transaction {
  id: number;
  entries: TransferEntry[];
}

// -- API calls --

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE_URL}${path}`, options);
  const text = await res.text();
  let body: any;
  try {
    body = JSON.parse(text);
  } catch {
    if (!res.ok) throw new Error(text || `Request failed: ${res.status}`);
    throw new Error("Invalid JSON response from server");
  }
  if (!res.ok) {
    throw new Error(body.error || `Request failed: ${res.status}`);
  }
  return body as T;
}

export function createAccount(name: string): Promise<Account> {
  return request<Account>("/accounts", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name }),
  });
}

export function submitTransfer(
  entries: TransferEntry[],
  idempotencyKey?: string
): Promise<TransferResult> {
  return request<TransferResult>("/transfers", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      entries,
      idempotency_key: idempotencyKey ?? crypto.randomUUID(),
    }),
  });
}

export function getBalance(accountId: number): Promise<BalanceResult> {
  return request<BalanceResult>(`/accounts/${accountId}/balance`);
}

export function getHistory(accountId: number): Promise<HistoryEntry[]> {
  return request<HistoryEntry[]>(`/accounts/${accountId}/history`);
}

export function getTransaction(transactionId: number): Promise<Transaction> {
  return request<Transaction>(`/transactions/${transactionId}`);
}
