import { ValidationPipe, ArgumentMetadata, BadRequestException } from '@nestjs/common';
import { CreateRoomDto } from './rooms/dto/create-room.dto';
import { PickSlotDto } from './rooms/dto/pick-slot.dto';
import { SwapRosterDto } from './rooms/dto/swap-roster.dto';
import { CheckPresenceDto } from './rooms/dto/check-presence.dto';
import { JoinRoomDto } from './rooms/dto/join-room.dto';
import { SpectateRoomDto } from './rooms/dto/spectate-room.dto';
import { ReconnectDto } from './rooms/dto/reconnect.dto';
import { ActivateAbilityDto } from './rooms/dto/activate-ability.dto';
import { PickSubDto } from './rooms/dto/pick-sub.dto';
import { SwapSubDto } from './rooms/dto/swap-sub.dto';
import { SpectatorReconnectDto } from './rooms/dto/spectator-reconnect.dto';

/**
 * Exercises the real ValidationPipe exactly as registered in main.ts
 * (`{ whitelist: true, forbidNonWhitelisted: true, transform: true }`)
 * against representative DTOs, since the gateway's own unit tests call
 * handlers directly — bypassing Nest's argument-resolution/pipe pipeline
 * entirely — and so never actually exercise this pipe. This is the only
 * place that does.
 */
describe('ValidationPipe (Task 1.2)', () => {
  const pipe = new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true });

  function metadata(type: new (...args: unknown[]) => unknown): ArgumentMetadata {
    return { type: 'body', metatype: type, data: '' };
  }

  it('a valid DTO passes through cleanly and is transformed into a real instance', async () => {
    const result = await pipe.transform(
      { displayName: 'Host', leagues: ['premier-league'], turnTimerSeconds: 30 },
      metadata(CreateRoomDto),
    );
    expect(result).toBeInstanceOf(CreateRoomDto);
    expect(result.displayName).toBe('Host');
    expect(result.turnTimerSeconds).toBe(30);
  });

  it('rejects a payload missing a required field', async () => {
    await expect(
      pipe.transform({ leagues: [] }, metadata(CreateRoomDto)),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a payload with a wrong-type field', async () => {
    await expect(
      pipe.transform({ turnId: 'not-a-uuid', slotIndex: 'not-a-number' }, metadata(PickSlotDto)),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a non-UUID playerId', async () => {
    await expect(
      pipe.transform(
        { playerId: 'not-a-uuid', roomCode: 'ABCDEF', reconnectToken: 'x' },
        metadata(CheckPresenceDto),
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('strips fields the DTO does not declare (whitelist) rather than silently passing them through', async () => {
    // forbidNonWhitelisted means an *unknown* extra field is rejected outright
    // (not silently dropped) — verifying that distinction explicitly, since
    // "strips extra fields" and "rejects unknown fields" are different
    // behaviors and the registered config deliberately chose the stricter one.
    await expect(
      pipe.transform(
        { displayName: 'Host', leagues: [], notARealField: 'haxx' },
        metadata(CreateRoomDto),
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('validates nested objects (ValidateNested + @Type) on SwapRosterDto', async () => {
    const valid = await pipe.transform(
      { a: { kind: 'pitch', index: 0 }, b: { kind: 'bench', group: 'att' } },
      metadata(SwapRosterDto),
    );
    expect(valid.a.kind).toBe('pitch');
    expect(valid.a.index).toBe(0);

    await expect(
      pipe.transform(
        { a: { kind: 'pitch' /* missing index */ }, b: { kind: 'bench', group: 'att' } },
        metadata(SwapRosterDto),
      ),
    ).rejects.toBeInstanceOf(BadRequestException);

    await expect(
      pipe.transform(
        { a: { kind: 'bogus-kind', index: 0 }, b: { kind: 'bench', group: 'att' } },
        metadata(SwapRosterDto),
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects a roomCode that is not exactly 6 letters', async () => {
    await expect(
      pipe.transform(
        { playerId: '11111111-1111-4111-8111-111111111111', roomCode: 'AB', reconnectToken: 'x' },
        metadata(CheckPresenceDto),
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  // ── High-risk room-access / gameplay DTOs ──────────────────────────────────

  it('accepts a valid JoinRoomDto', async () => {
    const result = await pipe.transform(
      { roomCode: 'ABCDEF', displayName: 'Guest' },
      metadata(JoinRoomDto),
    );
    expect(result).toBeInstanceOf(JoinRoomDto);
  });

  it('rejects JoinRoomDto with numeric roomCode', async () => {
    await expect(
      pipe.transform(
        { roomCode: '123456', displayName: 'Guest' },
        metadata(JoinRoomDto),
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('accepts SpectateRoomDto and ReconnectDto / SpectatorReconnectDto shapes', async () => {
    await expect(
      pipe.transform(
        { roomCode: 'ABCDEF', displayName: 'Spec' },
        metadata(SpectateRoomDto),
      ),
    ).resolves.toBeInstanceOf(SpectateRoomDto);

    const pid = '11111111-1111-4111-8111-111111111111';
    await expect(
      pipe.transform(
        { roomCode: 'ABCDEF', playerId: pid, reconnectToken: 'tok' },
        metadata(ReconnectDto),
      ),
    ).resolves.toBeInstanceOf(ReconnectDto);

    await expect(
      pipe.transform(
        { roomCode: 'ABCDEF', spectatorId: pid, reconnectToken: 'tok' },
        metadata(SpectatorReconnectDto),
      ),
    ).resolves.toBeInstanceOf(SpectatorReconnectDto);
  });

  it('rejects ActivateAbilityDto with negative slot index', async () => {
    await expect(
      pipe.transform({ ownSlotIndex: -1 }, metadata(ActivateAbilityDto)),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects PickSubDto / SwapSubDto with invalid positionGroup', async () => {
    await expect(
      pipe.transform(
        { positionGroup: 'gk', playerId: 'card-1' },
        metadata(PickSubDto),
      ),
    ).rejects.toBeInstanceOf(BadRequestException);

    await expect(
      pipe.transform(
        { positionGroup: 'gk', starterId: 'card-1' },
        metadata(SwapSubDto),
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
