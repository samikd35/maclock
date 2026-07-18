export class NativeCommandQueue {
  private tail: Promise<void> = Promise.resolve();

  constructor(private readonly onFailure: () => Promise<void>) {}

  enqueue(command: () => Promise<void>): void {
    this.tail = this.tail.then(command).catch(async () => {
      try {
        await this.onFailure();
      } catch {
        // The connection is already unusable; keep the queue drainable.
      }
    });
  }

  async drain(): Promise<void> {
    await this.tail;
  }
}
