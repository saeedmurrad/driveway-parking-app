import { BadRequestException, Controller, Module, Post, UploadedFile, UseGuards, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { diskStorage } from 'multer';
import { randomBytes } from 'crypto';
import { existsSync, mkdirSync } from 'fs';
import { extname, join } from 'path';
import { AuthGuard } from '../auth/auth.guard';

export const UPLOAD_DIR = process.env.UPLOAD_DIR ?? join(process.cwd(), 'uploads');
const OK = new Set(['image/jpeg', 'image/png', 'image/webp']);

/**
 * Photos for listings, parked-car check-ins and dispute evidence. Stored on local disk here;
 * point UPLOAD_DIR at a persistent volume or swap for S3 / Cloudflare R2 / Supabase Storage in production.
 */
@Controller('uploads')
@UseGuards(AuthGuard)
export class UploadsController {
  @Post()
  @UseInterceptors(FileInterceptor('file', {
    limits: { fileSize: 5 * 1024 * 1024 },
    fileFilter: (_req, file, cb) => (OK.has(file.mimetype) ? cb(null, true) : cb(new BadRequestException('Only JPEG, PNG or WebP images are allowed'), false)),
    storage: diskStorage({
      destination: (_req, _file, cb) => { if (!existsSync(UPLOAD_DIR)) mkdirSync(UPLOAD_DIR, { recursive: true }); cb(null, UPLOAD_DIR); },
      filename: (_req, file, cb) => cb(null, `${randomBytes(12).toString('hex')}${extname(file.originalname).toLowerCase() || '.jpg'}`),
    }),
  }))
  upload(@UploadedFile() file?: Express.Multer.File) {
    if (!file) throw new BadRequestException('No image received');
    return { url: `/uploads/${file.filename}` };
  }
}

@Module({ controllers: [UploadsController] })
export class UploadsModule {}
