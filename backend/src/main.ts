import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { ValidationPipe } from '@nestjs/common';
import { copyFileSync, existsSync, mkdirSync, readdirSync } from 'fs';
import { join } from 'path';
import { AppModule } from './app.module';
import { UPLOAD_DIR } from './uploads/uploads.controller';

/** Copy the bundled demo photos into the uploads folder (skips files that already exist). */
function seedPhotos() {
  const from = join(process.cwd(), 'seed-photos');
  if (!existsSync(from)) return;
  if (!existsSync(UPLOAD_DIR)) mkdirSync(UPLOAD_DIR, { recursive: true });
  for (const f of readdirSync(from)) if (!existsSync(join(UPLOAD_DIR, f))) copyFileSync(join(from, f), join(UPLOAD_DIR, f));
}

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { rawBody: true });
  app.enableCors({ origin: (process.env.CORS_ORIGINS ?? '').split(',').filter(Boolean) });
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
  seedPhotos();
  // Images are loaded cross-origin by the web app, so allow any origin to *read* them.
  app.useStaticAssets(UPLOAD_DIR, { prefix: '/uploads', setHeaders: (res) => res.set('Access-Control-Allow-Origin', '*') });
  await app.listen(process.env.PORT ?? 3000, '0.0.0.0');
}
bootstrap();
