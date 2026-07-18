export class NativeCommandQueue {
  private tail: Promise<void> = Promise.resolve();

  constructor(private readonly onFailure: () => void) {}

  enqueue(command: () => Promise<void>): void {
    this.tail = this.tail.then(command).catch(() => {
      this.onFailure();
    });
  }

  async drain(): Promise<void> {
    await this.tail;
  }
}
