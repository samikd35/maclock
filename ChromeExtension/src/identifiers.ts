const PROFILE_IDENTIFIER_MAXIMUM_BYTES = 128;

export function isValidProfileIdentifier(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    new TextEncoder().encode(value).length <=
      PROFILE_IDENTIFIER_MAXIMUM_BYTES &&
    /^[A-Za-z0-9_-]+$/.test(value)
  );
}

export function requireProfileIdentifier(value: unknown): string {
  if (!isValidProfileIdentifier(value)) {
    throw new Error("Invalid Chrome profile identifier");
  }
  return value;
}

export function requireChromeIdentifier(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0) {
    throw new Error("Invalid Chrome identifier");
  }
  return value as number;
}

export function isValidChromeIdentifier(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 0;
}
