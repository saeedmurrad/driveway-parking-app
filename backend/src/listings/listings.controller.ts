import { Controller, Get, NotFoundException, Param, Query } from '@nestjs/common';
import { DbService } from '../db/db.service';

@Controller('listings')
export class ListingsController {
  constructor(private readonly db: DbService) {}

  /** GET /listings/search?lat=&lng=&start=&end=&radius=&vehicleSize= */
  @Get('search')
  async search(
    @Query('lat') lat: string,
    @Query('lng') lng: string,
    @Query('start') start: string,
    @Query('end') end: string,
    @Query('radius') radius = '2000',
    @Query('vehicleSize') vehicleSize = 'medium',
  ) {
    const { rows } = await this.db.query(
      'select * from search_listings($1,$2,$3,$4,$5,$6)',
      [Number(lat), Number(lng), Number(radius), start, end, vehicleSize],
    );
    return rows;
  }

  @Get(':id')
  async one(@Param('id') id: string) {
    // Exact address + access instructions are deliberately NOT returned here;
    // they are released only with a paid booking.
    const { rows } = await this.db.query(
      `select id, title, latitude, longitude, space_type, max_vehicle_size, features,
              price_hour, price_day, cancellation_policy, booking_mode, rating
       from listings where id = $1 and status = 'live'`,
      [id],
    );
    if (!rows[0]) throw new NotFoundException();
    return rows[0];
  }
}
