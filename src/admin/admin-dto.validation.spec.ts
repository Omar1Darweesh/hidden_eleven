import { ValidationPipe, ArgumentMetadata, BadRequestException } from '@nestjs/common';
import { CreatePlayerDto, UpdatePlayerDto } from './dto/admin-player.dto';
import { CreateClubDto, UpdateAbilityDto } from './dto/admin-catalog.dto';
import { CreateFaqDto } from './dto/admin-content.dto';
import { SaveScoringConfigDraftDto } from './dto/admin-scoring.dto';
import { DEFAULT_SCORING_CONFIG_V1 } from '../game/scoring-config';

/**
 * Admin write DTOs — exercises the same ValidationPipe config as main.ts
 * so malformed admin bodies are rejected with 400 before AdminService runs.
 */
describe('Admin DTO ValidationPipe', () => {
  const pipe = new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
  });

  function metadata(type: new (...args: unknown[]) => unknown): ArgumentMetadata {
    return { type: 'body', metatype: type, data: '' };
  }

  const validPlayer = {
    name: 'Test Player',
    rating: 85,
    positions: ['ST'],
    nationality: 'England',
    club: 'Arsenal',
  };

  it('accepts a valid CreatePlayerDto', async () => {
    const result = await pipe.transform(validPlayer, metadata(CreatePlayerDto));
    expect(result).toBeInstanceOf(CreatePlayerDto);
    expect(result.rating).toBe(85);
  });

  it('rejects CreatePlayerDto with out-of-range rating', async () => {
    await expect(
      pipe.transform({ ...validPlayer, rating: 150 }, metadata(CreatePlayerDto)),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects CreatePlayerDto with unknown position', async () => {
    await expect(
      pipe.transform(
        { ...validPlayer, positions: ['NOT_A_POS'] },
        metadata(CreatePlayerDto),
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects CreatePlayerDto with unknown extra fields', async () => {
    await expect(
      pipe.transform(
        { ...validPlayer, injected: 'evil' },
        metadata(CreatePlayerDto),
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('accepts partial UpdatePlayerDto', async () => {
    const result = await pipe.transform(
      { rating: 90 },
      metadata(UpdatePlayerDto),
    );
    expect(result.rating).toBe(90);
  });

  it('rejects CreateClubDto missing league', async () => {
    await expect(
      pipe.transform({ name: 'Arsenal' }, metadata(CreateClubDto)),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects UpdateAbilityDto with bad colour', async () => {
    await expect(
      pipe.transform({ color: 'yellow' }, metadata(UpdateAbilityDto)),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('accepts valid CreateFaqDto', async () => {
    const result = await pipe.transform(
      {
        question: 'How do I play?',
        answer: 'Draft a team.',
        order: 1,
        visible: true,
      },
      metadata(CreateFaqDto),
    );
    expect(result).toBeInstanceOf(CreateFaqDto);
  });

  it('accepts DEFAULT_SCORING_CONFIG_V1 as SaveScoringConfigDraftDto', async () => {
    const result = await pipe.transform(
      DEFAULT_SCORING_CONFIG_V1,
      metadata(SaveScoringConfigDraftDto),
    );
    expect(result.userChallenges.rewardPerChallenge).toBe(5);
  });

  it('rejects SaveScoringConfigDraftDto with missing nested object', async () => {
    await expect(
      pipe.transform(
        { userChallenges: { rewardPerChallenge: 5 } },
        metadata(SaveScoringConfigDraftDto),
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
