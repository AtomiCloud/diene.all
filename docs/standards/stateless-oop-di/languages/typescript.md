# Stateless OOP with DI in TypeScript/Bun

## Folder Structure

```text
src/
  lib/                    # Domain layer — pure code
    identity/             # Bounded context
      user/
        structures.ts     # User, UserRecord
        interfaces.ts     # IUserRepository, ILogger
        service.ts        # UserService
    commerce/             # Bounded context
      order/
        structures.ts
        service.ts
  adapters/               # Adapter layer — impure code
    identity/             # Bounded context
      user/
        api/
          controller.ts
          req.ts
          res.ts
          mapper.ts
        data/
          repo.ts
          mapper.ts
```

## Structures (Pure Data)

```typescript
// src/lib/identity/user/structures.ts
interface User {
  id: string;
  name: string;
  email: string;
}

interface UserRecord {
  name: string;
  email: string;
}
```

## Interfaces (Dependency Contracts)

```typescript
// src/lib/identity/user/interfaces.ts
interface ILogger {
  log(message: string): void;
}

interface IUserRepository {
  findById(id: string): Promise<User | null>;
  save(user: User): Promise<void>;
}
```

## Stateless Service

```typescript
// src/lib/identity/user/service.ts
class UserService {
  constructor(
    private readonly repo: IUserRepository,
    private readonly logger: ILogger,
  ) {}

  async create(record: UserRecord): Promise<User> {
    this.logger.log(`Creating user: ${record.name}`);
    const user: User = { id: crypto.randomUUID(), ...record };
    await this.repo.save(user);
    return user;
  }
}
```

## Entry Point Wiring

```typescript
// src/main.ts
const logger = new ConsoleLogger();
const repo = new PostgresUserRepo(pool);
const userService = new UserService(repo, logger);
```

## Adapter (Impure Implementation)

```typescript
// src/adapters/identity/user/data/repo.ts
class PostgresUserRepo implements IUserRepository {
  constructor(private readonly pool: Pool) {}

  // Pseudo code — demonstrates adapter pattern
  async findById(id: string): Promise<User | null> {
    const row = await this.pool.query('SELECT * FROM users WHERE id = $1', [id]);
    const r = row.rows[0];
    if (!r) return null;
    // Map raw row to domain type (see data/mapper.ts)
    return { id: r.id, name: r.name, email: r.email };
  }

  async save(user: User): Promise<void> {
    await this.pool.query(
      'INSERT INTO users (id, name, email) VALUES ($1, $2, $3) ON CONFLICT (id) DO UPDATE SET name = $2, email = $3',
      [user.id, user.name, user.email],
    );
  }
}

// ConsoleLogger adapter for domain ILogger interface
class ConsoleLogger implements ILogger {
  log(message: string): void {
    console.log(message);
  }
}
```
